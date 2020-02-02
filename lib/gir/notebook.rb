require 'base64'
require 'rbnacl'
require 'io/console'

class Notebook
  attr_accessor :notebook, :encrypt, :collection, :tag_table, :schema, :tag_relations, :key, :salt, :box, :strings, :schema_strings, :type, :ui
 

  def initialize(notebook, collection, schema, ui, encrypted=false, tagtable=false, type = 'sql')
    self.ui = ui
    self.type = type
    self.backend notebook
    self.set_collection_name(collection)
    self.set_tags(tagtable)
    self.tag_relations="links_"+self.tag_table
    self.schema=schema
    self.prepare_schema(schema)
    self.encrypt = encrypted
    if self.encrypt
      self.prepare_box
    end
  end
  
  def _sql_backend(notebook)
    require 'sqlite3'
    self.notebook = SQLite3::Database.new notebook
    self.strings = { :add_tag_to_note => "insert into %s (note_id,tag_id ) VALUES (%s, %s)",
                     :del_tag_to_note => "delete from %s where ( note_id, tag_id ) = ( %s, %s )",
                     :salt_table => "create table if not exists salt ( collection TEXT UNIQ, salt TEXT UNIQ )",
                     :grab_salt => "select salt from salt where collection = '%s'",
                     :add_salt => "insert into salt ( collection, salt ) VALUES ( '%s' , '%s' )",
                     :inserter => "insert into %s (%s) VALUES (%s)",
                     :add_tag => "insert into %s (tag) VALUES ('%s')",
                     :update_note => "update %s set %s = '%s' where note_id = %s",
                     :tag_id => "SELECT tag_id from %s where tag = '%s'",
                     :get_tags_id => "SELECT tag_id from %s where note_id = %s",
                     :get_notes_id => "SELECT note_id from %s where tag_id = %s",
                     :get_tag => "SELECT tag from %s where tag_id = %s",
                     :query => "SELECT %s from %s where %s = %s ",
                     :get_name => "SELECT name from %s where note_id = %s",
                     :enable_foreign => "PRAGMA foreign_keys=on",
                     :del_note => "DELETE FROM %s where note_id = %s",
                     :insert_id => "select last_insert_rowid()",
                     :get_all => "select * from %s"
                   }
    self.schema_strings = { :note_table => "create table if not exists %s ( note_id INTEGER PRIMARY KEY, %s )",
                            :tag_table => "create table if not exists %s ( tag_id INTEGER PRIMARY KEY, tag TEXT )",
                            :tag_link_table => "create table if not exists %s ( note_id INTEGER, tag_id INTEGER, PRIMARY KEY ( note_id, tag_id ), FOREIGN KEY ( note_id ) REFERENCES %s (note_id) ON DELETE CASCADE, FOREIGN KEY (tag_id) REFERENCES %s ( tag_id ) ON DELETE CASCADE)"
                          }
  end
  
  def backend(notebook)
    case self.type
    when 'sql'
      self._sql_backend(notebook)
    else
      puts 'Unsupported type'
    end
  end
  
  def runner(*command)
    case self.type
    when 'sql'
      if command.length == 2
        result = self.notebook.execute command[0], command[1]
      else
        result = self.notebook.execute command[0]
      end
      case result.length
      when 0
        return nil
      when 1
        if result[0].length == 1
          return result[0][0]
        else
          return result.flatten
        end
      else
        return result
      end
    else
      puts 'something funky'
    end
  end
  
  def prepare_box
    opslimit = 5
    memlimit = 7_256_678
    digest_size = 32
    self.notebook.execute(self.strings[:salt_table])
    possiblesalts = self.runner( self.strings[:grab_salt] % [self.collection])
    unless possiblesalts == nil
      self.salt = Base64.decode64 possiblesalts
      exists = true
    else
      self.salt = RbNaCl::Random.random_bytes(RbNaCl::PasswordHash::Argon2::SALTBYTES)
      self.runner(self.strings[:add_salt] % [ self.collection, (Base64.encode64 self.salt) ])
      exists = false
    end
    done = 1
    until done == 3
      begin
        password = self.ui.password_handler(exists)
        self.box = RbNaCl::SimpleBox.from_secret_key(RbNaCl::PasswordHash.argon2(password,self.salt,opslimit,memlimit,digest_size))
        done = 3
      rescue
        self.ui.alert "Invalid Password"
        done+=1
      end
    end
  end

  def set_collection_name(collection)
    self.collection = collection.downcase.sub(' ', '_').strip
  end

  def set_tags(tag_name=false)
    if tag_name == false
      tag_name = "tags_"+self.collection
    end
    self.tag_table = tag_name
  end
  
  def prepare_data(content, encrypted=false)
    keys = content.keys
    tags = []
    if keys.include? "tags"
      tags = content["tags"]
      content.delete "tags"
    end
    for key,value in content
      if self.encrypt
        content[key] = (Base64.encode64 self.box.encrypt(value))
      else
        content[key] = (Base64.encode64 value).strip
      end
    end
    return content, tags
  end

  def prepare_tags(tags)
    for tag in tags
        tag.strip!
        tag.downcase!
    end
    tags = tags.map{|tag| (Base64.encode64 tag).strip}
    return tags
  end
  
  def add_note(content,encrypted=false)
    content,tags = self.prepare_data(content,encrypted)
    insertstring = self.strings[:inserter] % [self.collection,(content.keys).join(','),('?,'*((content.keys).length)).chomp(',')]
    self.runner(insertstring,content.values)
    unless tags.length == 0
      id = self.insert_id
      self.add_tags(tags,id)
    end
  end

  def insert_id
    return self.runner(self.strings[:insert_id])
  end

  def delete_note(id)
    self.runner(self.strings[:del_note] % [self.collection,id])
  end

  def prepare_schema(schema)
    self.runner(self.schema_strings[:note_table] % [ self.collection, schema.join(" TEXT,").chomp(',')] )
    self.runner(self.schema_strings[:tag_table] % [self.tag_table] )
    self.runner(self.schema_strings[:tag_link_table] % [ self.tag_relations,self.collection,self.tag_table ] )
    self.runner(self.strings[:enable_foreign])
  end

  def update_note(content, id)
    content, tags = self.prepare_data(content)
    for key,value in content
      self.runner(self.strings[:update_note] % [ self.collection, key ,value,id])
    end
  end

  def _remove_tags(tags, id)
    tags = self.prepare_tags(tags)
    for tag in tags
      exists = self.runner(self.strings[:tag_id] % [self.tag_table,tag])
      unless exists == nil
        self.runner(self.strings[:del_tag_to_note] % [self.tag_relations,id,exists]);
      end
    end
  end
  
  def _remove_enc_tags(tags, id)
    tags = tags.map{ |tag| tag.downcase.strip }
    existing_tags = self.get_tags(id)
    for tag_id,tag in existing_tags
      if tags.include? tag
        self.runner(self.strings[:del_tag_to_note] % [self.tag_relations,id,tag_id])
      end
    end
  end

  def remove_tags( tags, id )
    if self.encrypt
      self._remove_enc_tags
    else
      self._remove_tags
    end
  end

  def get_all_tags
    tags = self.runner(self.strings[:get_all] % [ self.tag_table ])
    unless tags == nil
      if tags[0].is_a? Array
        existing_tags = Hash[tags]
      else
        existing_tags = Hash[[tags]]
      end
      for key,value in existing_tags
        if self.encrypt
          existing_tags[key] = self.box.decrypt((Base64.decode64(value))).strip
        else
          existing_tags[key] = (Base64.decode64 value).downcase.strip
        end
      end
      return existing_tags
    end
    return {}
  end
  
  def _add_enc_tags(tags,id)
    tags = tags.map{ |tag| (tag.downcase).strip }
    existing_tags = self.get_all_tags
    for key,value in existing_tags
      if tags.include? value
        tags.delete value
        self.runner(self.strings[:add_tag_to_note] % [self.tag_relations,id, (existing_tags.key(value))])
      end
    end
    for tag in tags
      self.runner(self.strings[:add_tag] % [self.tag_table,(Base64.encode64 (self.box.encrypt(tag)))])
      tag_id = self.insert_id
      self.runner(self.strings[:add_tag_to_note] % [self.tag_relations,id,tag_id])
    end
  end
  
  def _add_tags(tags, id)
    tags = self.prepare_tags(tags)
    for tag in tags
      exists = self.runner(self.strings[:tag_id] % [self.tag_table,tag])
      if exists == nil
        self.runner(self.strings[:add_tag] % [self.tag_table,tag])
        tag_id = self.insert_id
      else
        tag_id = exists
      end
      self.runner(self.strings[:add_tag_to_note] % [ self.tag_relations, id, tag_id])
    end
  end

  def add_tags(tags,id)
    if self.encrypt
      self._add_enc_tags(tags,id)
    else
      self._add_tags(tags,id)
    end
  end

  def query_notes(value,query)
    unless query == 'note_id'
      query = "'%s'" % [(Base64.encode64 query).strip]
    end
    results = {}
    for item in self.schema
      if self.encrypt
        v = self.runner(self.strings[:query] % [item,self.collection,query,value])
        returnv = self.box.decrypt(Base64.decode64 v)
      else
        v = self.runner(self.strings[:query] % [item,self.collection,query,value])
        returnv = Base64.decode64 v
      end
      results[item] = returnv
    end
    return results
  end

  def get_tags(id)
    tags = []
    items = [(self.runner(self.strings[:get_tags_id] % [self.tag_relations,id]))].flatten
    for tag in items
      taget = Base64.decode64(self.runner(self.strings[:get_tag] % [self.tag_table, tag]))
      if self.encrypt
        decrypted = self.box.decrypt(taget).downcase.strip
        tags.append(decrypted)
      else
        tags.append(taget.downcase.strip)
      end
    end
    return Hash[items.zip(tags)]
  end

  def _get_enc_notes(tag)
    tags = self.get_all_tags
    key = tags.key tag
    notes = []
    if key != nil
      items = [(self.runner(self.strings[:get_notes_id] % [self.tag_relations,key]))].flatten
      for note in items
        notes.append(self.box.decrypt(Base64.decode64 self.runner(self.strings[:get_name] % [self.collection,note])))
      end
    end
    return Hash[items.zip(notes)]
  end
  
  def _get_notes(tag)
    notes = []
    id = self.runner(self.strings[:tag_id] % [self.tag_table,(Base64.encode64 (tag.downcase).strip).strip])
    unless id == nil
      items = [(self.runner(self.strings[:get_notes_id] % [self.tag_relations,id]))].flatten
      for note in items
        #puts self.strings[:get_name] % [self.collection,note]
        unless note == nil
          notes.append(Base64.decode64 self.runner(self.strings[:get_name] % [self.collection,note]))
        end
      end
      return Hash[items.zip(notes)]
    end
  end

  def get_notes(tag)
    if self.encrypt
      self._get_enc_notes(tag)
    else
      self._get_notes(tag)
    end
  end
  
end
