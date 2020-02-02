require 'io/console'

class GirTui
  attr_accessor :config, :utils
  def initialize
  end

  def password_handler(exists)
    if exists
      print "Enter Password: "
      $stdout.flush
      password = STDIN.noecho(&:gets).chomp
      puts ""
    else
      done = false
      until done
        print "Enter Password: "
        $stdout.flush
        password1 = STDIN.noecho(&:gets).chomp
        puts ""
        print "Re-Enter Password: "
        $stdout.flush
        password2 = STDIN.noecho(&:gets).chomp
        puts ""
        if password1 == password2
          done = true
          password = password1
        end
      end
    end
    return password
  end

  def alert(string)
    puts string
  end

  def start_config
    self.utils.write_config(file,config)
  end

end
