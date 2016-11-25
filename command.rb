require 'colorize'
require 'pry'

module Command
  
  def self.ls
    Dir["*"].map{ |str| "#{str}\n\r" }.join
  end

  def self.cd arg=nil
    Dir.chdir(arg)
    "OK.\n\r".green
  rescue
    "No such file or directory - #{ arg.inspect }\n\r"
  end

  def self.time
    Time.now.strftime("Sever time: %d.%m.%Y %T \n\r")
  end

  def self.upload arg

  end

end
