require 'io/console'
require 'tempfile'
require 'tty-editor'

class GirTui
  attr_accessor :config, :utils, :strs
  def initialize(lang, util)
    self.strs = self.set_strings(lang)
    self.utils = util
  end

  def set_strings(lang)
    case lang
    when 'en'
      self.set_en_strings
    else
      self.set_en_strings
    end
  end

  def set_en_strings
    self.strs = {
      :config => {
        :notebook => "Default notebook name?[notebook] ",
        :db => "Default db location?[%s]",
        :encrypt => "Encrypt by default?",
        :schema => "Default schema?[default]"
      },
      :password => {
        :enter => "Enter Password: ",
        :renter => "Re-Enter Password: ",
        :match => "Passwords do not match!",
        :invalid => "Invalid Password!"
      }
    }
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

  def cinput(query, default, acceptable)
    done = false
    puts acceptable
    until done
      answer = self.ainput(query,default)
      puts acceptable.inspect
      if acceptable.include? answer
        done = true
      end
    end
    return answer
  end

  def ainput(query,default)
    print query
    answer = gets
    answer.strip!
    if answer == ''
      return default
    else
      return answer
    end
  end

  def dirinput(query,default)
    done = false
    until done
      answer = ainput(query,default)
      if Dir.exists? File::dirname(answer)
        done = true
      end
    end
    return answer
  end

  def start_config(conffile)
    config = {}
    config["notebook"] = ainput(self.strs[:config][:notebook], "notebook")
    defaultdb =  File.join(File::dirname(conffile), ".gir.db")
    config["db"] = self.dirinput(self.strs[:config][:db] % [defaultdb] , defaultdb)
    config["encrypted"] = self.cinput(self.strs[:config][:encrypt], 'false', [ 'true','false'])
    self.utils.write_config(config, conffile)
    return config
    end

  def edit_note(note_id, notebook)
    note = notebook.get_a_note(note_id)['note']
    file = Tempfile.new()
    file.write(note)
    file.close
    TTY::Editor.open(file.path)
    returnf = File.read(file.path)
    File.delete(file.path)
    return returnf
  end

  def write_note
    file = Tempfile.new
    file.close
    TTY::Editor.open(file.path)
    returnf = File.read(file.path)
    File.delete(file.path)
    return returnf
  end

  def list_select(hash,prompt)
    done = false
    selection = 0
    until done
      for key,value in hash
        puts key.to_s+": "+value.to_s
      end
      print prompt+": "
      selection = gets
      if hash.has_key? selection.to_i
        done = true
      else
        puts "Invalid selection!"
      end
    end
    return selection
  end

end
