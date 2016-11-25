require 'socket'
require 'colorize'
require './command'
require 'pry'

class Server
  include Socket::Constants
  include Command
  def initialize(ip_address: 'localhost', port: '3000', package_size: 64)
    @ip_address = ip_address
    @port = port
    @package_size = package_size
    @header_size = 40
    open_server
    @clients = []
    wait_clients
  end

  def open_server
    @server = Socket.new AF_INET, SOCK_STREAM, 0
    @server.bind( Socket.sockaddr_in(@port, @ip_address) )
    @server.listen(5)
    puts 'Server is running!'
  end

  def wait_clients
    puts "Waiting clients"
    loop do
      if (soket =  @server.accept)
        @client, @client_address = soket
        puts "Connected client with ip: #{address}"
        check_client
        listen_client
      end
    end
  end

  def check_client
    if current_client
      continue_downloading if current_client[:download_file_name]
      continue_uploading if current_client[:upload_file_name]
    else
      @client.send "Welcome to server\r\nYou can enter commands: ls <dir> | cd <dir> | echo <> | time |shutdown\r\n", 0
      save_client(address)
    end
  end

  def continue_downloading
    message = 'download_continue ' + current_client[:download_file_name].to_s + ' ' + current_client[:download_file_size].to_s
    @client.send(message, 0)
    get_file(current_client[:download_file_name], 'a')
  end

  def continue_uploading
    message = 'upload_continue ' + current_client[:upload_file_name].to_s
    @client.send(message, 0)
    file_downloaded_size = @client.recv(50)
    send_file(current_client[:upload_file_name], file_downloaded_size)
  end


  def current_client
    @clients.select {|client| client[:address] == address}.first
  end

  def address
    @client_address.ip_address
  end

  def save_client address
    client = {}
    client[:address] = address
    client[:upload_file_name] = nil
    client[:upload_file_size] = nil
    client[:download_file_name] = nil
    client[:download_file_size] = nil
    @clients.push(client)
  end

  def save_download_information file_name, file_size
    @clients.each do  |client|
      if client[:address] == address
        client[:download_file_name] =  file_name
        client[:download_file_size] =  file_size
      end
    end
  end

  def save_upload_information file_name
    @clients.each do  |client|
      if client[:address] == address
        client[:upload_file_name] =  file_name
        #client[:upload_file_size] =  file_size
      end
    end
  end

  def listen_client
    loop do
      inputs = @client.recv(50) 
      cmd, arg = inputs.split
      case cmd
        when "ls" then @client.send(Command.ls, 0)
        when "cd" then @client.send(Command.cd(arg), 0)
        when "shutdown", 'close', 'exit', 'quit' then @client.close; return
        when "echo" then  @client.puts arg
        when "time" then  @client.send(Command.time, 0)
        when 'download' then send_file(arg)
        when 'upload' then get_file(arg) 
        else
          @client.send("Invalid Command!\n\r", 0)
          print inputs
      end
    end
  rescue Errno::ENOENT
    STDERR.puts 'No such file! Use the <ls> command'
  rescue Errno::EPIPE
    STDERR.puts "Connection broke!"
    @client.close
    wait_clients
  rescue Errno::ECONNRESET
    STDERR.puts "Connection reset by peer!"
  end

  def invalid_command inputs
    @client.send("\r", 0) if inputs == "" && inputs != "\n\n"
    @client.send("Invalid Command!\n\r", 0) if inputs != "" && inputs != "\n\n"

  end

  def header file_size, signal="send"
    header = "%0#{@header_size}b" % file_size
    header[0] = "0" if signal == "send"
    header[0] = "1" if signal == "eof"
    header
  end

  def send_file file_name, file_position=0
    file = open("./#{file_name}", 'rb')
    send_size = file_position.to_i
    file.pos = file_position.to_i
    while file.size > send_size
      package_data = file.read(@package_size-@header_size)
      package_header = file.eof? ? header(file.size, "eof") : header(file.size)
      send_size += @client.send(package_header + package_data, 0)
      send_size -= package_header.size
    end
    file.close
    message = @client.recv(50)
    if message == 'success'
      save_upload_information(nil)
      puts "File #{file_name} successfully uploaded to client #{address}"
    else
      save_upload_information(file_name)
      @client.close
      wait_clients
    end
  rescue Errno::ENOENT
    @client.send('No such file! Use the <ls> command',0)
  rescue Errno::EPIPE
    STDERR.puts "Connection broke!"
    save_upload_information(file_name)
  rescue Errno::ECONNRESET
    STDERR.puts "Connection reset by peer!"
    save_upload_information(file_name)
    @client.close
    file.close
    wait_clients
    #retry
  end

  def get_file file_name, file_mode='wb'
    puts "Downloading #{file_name}"
    file = File.open("server/#{file_name}", file_mode)
    while true
      package = @client.recv(@package_size, 0)
      file.print package[@header_size..-1]
      break if signal_eof?(package) || package.empty?
      must_file_size = must_file_size package
    end

    if file.size == must_file_size
      puts 'File successfully downloaded.'
      save_download_information(nil, nil)
      @client.send "File successfully uploaded.\n", 0
    else
      puts 'Fail download.'
      save_download_information(file_name, file.size)
      @client.send "fail file_size #{file.size}", 0
    end
    file.close
  end

  def signal_eof? package
    package[0] == "1" ? true : false
  end

  def must_file_size package
    header = package[0...@header_size]
    header[0] = "0"
    header.to_i(2)
  end
end
