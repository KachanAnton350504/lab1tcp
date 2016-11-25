require 'socket'
require 'pry'
require 'colorize'

class Client
  include Socket::Constants

  def initialize(ip_address: 'localhost', port: '3000', package_size: 64)
    @ip_address = ip_address
    @port = port
    @package_size = package_size
    @header_size = 40
    connect_to_server
    send_server
  end

  def connect_to_server
    @server = Socket.new(AF_INET, SOCK_STREAM, 0)
    @server.connect( Socket.sockaddr_in(@port, @ip_address) )
    message = @server.recv(2048)
    print message
    command, *argument = message.split
    send_file(argument[0], argument[1]) if command == 'download_continue'
    download_continue(argument[0]) if command == 'upload_continue'
  end

  def download_continue file_name
    file = File.open("client/#{file_name}", 'rb')
    @server.send "#{file.size}", 0
    file.close
    get_file(file_name, 'a')
  end

  def send_server
    loop do
      message = $stdin.gets.chomp
      @server.send(message + "\n\r",0)
      command, argument = message.split
      send_file argument if command == 'upload'
      get_file argument if command == 'download'
      print @server.recv(2048) if command != 'upload' || command != 'download'
    end
  rescue Errno::ENOENT
    STDERR.puts 'No such file! Use the <ls> command'
  rescue Errno::EPIPE
    STDERR.puts "Connection broke!"
    @server.close
    connect_to_server
  rescue Errno::ECONNRESET
    STDERR.puts "Connection reset by peer!"
  end

  def signal_eof? package
    package[0] == "1" ? true : false
  end

  def must_file_size package
    header = package[0...@header_size]
    header[0] = "0"
    header.to_i(2)
  end

  def get_file file_name, file_mode='wb'
    puts "Downloading #{file_name}"
    file = File.open("client/#{file_name}", file_mode)
    while true
      package = @server.recv(@package_size,0)
      file.print package[@header_size..-1]
      break if signal_eof?(package) || package.empty?
      must_file_size = must_file_size package
    end

    if file.size == must_file_size
      puts 'File successfully downloaded.'
      @server.send "success", 0
    else
      puts 'Fail download.'
      @server.send "Fail! Size of uploaded file:#{file.size} bytes", 0
    end
    file.close
  end

  def header file_size, signal="send"
    header = "%0#{@header_size}b" % file_size
    header[0] = "0" if signal == "send"
    header[0] = "1" if signal == "eof"
    header
  end

  def send_file file_name, file_position=0
    file = open("./#{file_name}", "rb")
    send_size = file_position.to_i
    file.pos = file_position.to_i
    while file.size > send_size
      package_data = file.read(@package_size-@header_size)
      package_header = file.eof? ? header(file.size, "eof") : header(file.size)
      send_size += @server.send(package_header + package_data, 0)
      send_size -= package_header.size
    end
    file.close
  end
end