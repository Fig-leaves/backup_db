require 'mysql2'
require 'csv'
require 'google/api_client'
require "google_drive"
require "tempfile"

DBNAME = "csr_development"
PASSWD = ""
HOST = "localhost"
USERNAME = "root"
FOLDER_NAME = "backup"
#FOLDER_NAME = Time.now.strftime("backup_%Y-%m-%d")

client = Mysql2::Client.new(:host => HOST, :username => USERNAME, :password => PASSWD, :database => DBNAME)

drive_client = Google::APIClient.new(
    :application_name => "backup_tool",
    :application_version => "1.0.0"
)

session = GoogleDrive.login_with_oauth("4/3y4pSJao3LTIIk6OcPXzWgsN6Kcqc5Pi6oF81I-PwEE")

begin
    session.files.each do |file|
      puts file.title
    end
rescue 
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

    File.open("./" + table_name + ".csv", 'w:cp932') do |file|
        file.write(csv_string)
    end
end


