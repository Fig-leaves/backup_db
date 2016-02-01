require 'mysql2'
require 'csv'
require 'google/api_client'
require "google_drive"
require "tempfile"
require "json"
require 'logger'
require 'clockwork'

DBNAME = "csr_development"
PASSWD = ""
HOST = "localhost"
USERNAME = "root"
FOLDER_NAME = "backup"
CONFIG_PATH = "./config.json"

log = Logger.new("./backup.log")



module BackupCron 
    
    def start_backup
        client = Mysql2::Client.new(:host => HOST, :username => USERNAME, :password => PASSWD, :database => DBNAME)

        drive_client = Google::APIClient.new(
            :application_name => "backup_tool",
            :application_version => "1.0.0"
        )

        begin
            json_data = open(CONFIG_PATH) do |io|
              JSON.load(io)
            end
            session = GoogleDrive.login_with_oauth(json_data["access_token"])
            access_token = json_data["access_token"]

            log.info("Successfly login")
            
        rescue 
            log.info("failed login as access_token")
            log.info("Start auth login....")
            drive = drive_client.discovered_api("drive", "v2")
            auth = drive_client.authorization
            auth.client_id = "365676459893-hibpmb3bkq9kfnlvmpkf3s0ns7t76ff9.apps.googleusercontent.com"
            auth.client_secret = "DDSLCa-WSLuF4Wa7TmDyY3D5"
            auth.scope = "https://www.googleapis.com/auth/drive"
            auth.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
            uri = auth.authorization_uri

            puts "  Open browser with this uri: #{uri}" 
            $stdout.write  "Enter authorization code: "
            auth.code = gets.chomp
            auth.fetch_access_token!

            access_token = auth.access_token
            refresh_token = auth.refresh_token
            json_data = Hash.new
            json_data["access_token"] = access_token
            log.info("success auth login")

            open(CONFIG_PATH, 'w') do |io|
              JSON.dump(json_data, io)
            end
        end

        table_name = []
        client.query("show tables").each do |table|
            table_name.push table["Tables_in_"+ DBNAME]
        end
        session = GoogleDrive.login_with_oauth(access_token)
        folder = session.file_by_title(FOLDER_NAME)
        session.root_collection.remove(folder)
        session.root_collection.create_subcollection(FOLDER_NAME)

        table_name.each do |table_name|
            csv_string = CSV.generate(:force_quotes => true) do |csv|
                column_name = []
                client.query("show columns from " + table_name).each do |data|
                    column_name.push(data["Field"])
                end    
                csv << column_name
                client.query("select * from " + table_name).each do |data|
                    row = []
                    column_name.each do |name|
                        row.push data[name]
                    end
                    csv << row
                end
            end

            Tempfile.open(["./" + table_name + ".csv", ".csv"]) do |file|
                file << csv_string
                session.upload_from_file(file, table_name + ".csv" )
                file_name = session.file_by_title(table_name + ".csv")
                folder = session.file_by_title(FOLDER_NAME)
                folder.add(file_name)
                session.root_collection.remove(file_name)
            end
            log.info("save backup file named " + table_name + ".csv")

            #File.open("./" + table_name + ".csv", 'w:cp932') do |file|
            #    file.write(csv_string)
            #end
        end

        log.info("Complete saved " + table_name.length + " files!!!")

    end

    handler do |job|
        self.send(job.to_sym)
    end

    every(1.hour, 'start_backup')

end


