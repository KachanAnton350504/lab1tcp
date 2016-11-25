require './server1.rb'
require './client.rb'



puts "Client - 0, Server - 1"
message = $stdin.gets.chomp
if message == '0'
  Client.new
else 
  Server.new
end

