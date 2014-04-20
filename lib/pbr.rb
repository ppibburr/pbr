module PBR
  # @return [String] the proccess' current directory
  def self.getwd
    GLib.get_current_dir
  end
  
  # Change proccess directory
  #
  # @param [String] path, the directory to change to
  def self.chdir path
    GLib.chdir(path)
  end
  
  class Environ < Hash
    def to_a
      map do |k,v|
        "#{k}=#{v}"
      end   
    end
  end
  
  # @return [Hash] map of enviroment variables and thier values
  def self.env
    return @env if @env
    
    @env = Environ.new
    
    GLib.get_environ.each do |q|
      d = q.split("=")
      key = d.shift
      val = d.join("=")
      @env[key] = val
    end
    
    return @env
  end

  # Execute a system command. Child inherits parents environment, STDOUT and STDERR. Blocking
  # 
  # @param [String] str, the command to execute
  # @return [::Object], true on success, false on child abnormal exit, nil on execution error
  def self.system str
    env = PBR.env.to_a
  
    q = GLib::spawn_sync [str], PBR.getwd, env, GLib::SpawnFlags::SEARCH_PATH | GLib::SpawnFlags::SEARCH_PATH_FROM_ENVP, false, false
    
    begin GLib::spawn_check_exit_status q[0]
      return true
    rescue
      return false
    end
    
  rescue => e
    return nil
  end
  
  # Execute a system command. Child inherits parents environment, STDOUT and STDERR. Blocking
  # 
  # @param [String] str, the command to execute
  # @return [::Object], true on success, false on child abnormal exit, nil on execution error
  def self.x str
    env = PBR.env.to_a
  
    q = GLib::spawn_sync [str], PBR.getwd, env, GLib::SpawnFlags::SEARCH_PATH | GLib::SpawnFlags::SEARCH_PATH_FROM_ENVP, true, false
    
    return q[1]
  end  
  
  # Read a file
  #
  # @param [String] path, the file to read
  # @return [String] the contents of file
  def self.read path
    GLib::File.get_contents(path)
  end

  # Write contents to a file
  #
  # @param [String] path, the file to write to
  # @param [String] str, the contents  
  def self.write path, str
    GLib::File.set_contents(path, str)
  end
  
  class FileExistsError < Exception
  end
  
  class DirectoryCreateError < Exception
  end
  
  # @param [String] path, the directory to create
  # @param [Integer] mode
  def self.mkdir path, mode = 0700
    if GLib::file_test path, GLib::FileTest::EXISTS
      raise FileExistsError.new("File exits: #{path}")
    end
    
    unless GLib.mkdir path, mode
      raise UnhandledDirectoryCreateError.new("Creating: #{path} with mode: #{mode}, failed")
    end
    
    true
  end  
  
  # Format a file size in human readable form
  #
  # @param [Integer] size, the file size to format
  # @return [String] formatted to represent the file size
  def self.format_size size
    GLib::format_size size
  end
  
  # @return [String] the basename of +path+
  def self.basename path
    GLib::path_get_basename path
  end
  
  # @return [String] the dirname of +path+  
  def self.dirname path
    GLib::path_get_dirname(path)
  end
  
  # Joins strings to make a path with the correct separator
  #
  # @return [String] the resulting path
  def self.build_path *args
    args << nil
    GLib::build_filenamev args
  end
  
  # Object representing a popen call
  class POpened
    # Wraps a GLib::IOChannel
    class self::Stream
      attr_reader :channel
    
      # @param [Proc] b, the block to call when data has been read
      def on_read &b
        @on_read = b
      end
      
      # @param [String] str, data to write
      def write str
        len = str.length
        @channel.write_chars str, len
        @channel.flush
      end
      
      # @return [Boolean] end of file
      def eof?
        !!@eof
      end
      
      def close
        @closed = true
      end
      
      def closed?
        eof? || !!@closed
      end
      
      private
      def line_read s
        return if closed?
        return unless @on_read
        
        @on_read.call s
      end
    end
    
    attr_accessor :input,:output, :error
    def initialize
      @input  = Stream.new
      @output = Stream.new
      @error  = Stream.new
    end
    
    # Performs the popen call. Stream readers should already be implemented before calling
    #
    # @return [Array]<PBR::POpened, Integer>, the instance, and the childs' PID
    def run *argv
      env = PBR.env.to_a
      
      pid, i, o, e = GLib::spawn_async_with_pipes argv, PBR.getwd, env, GLib::SpawnFlags::DO_NOT_REAP_CHILD | GLib::SpawnFlags::SEARCH_PATH | GLib::SpawnFlags::SEARCH_PATH_FROM_ENVP
 
      in_ch  = GLib::IOChannel.unix_new( i );      
      out_ch = GLib::IOChannel.unix_new( o );
      err_ch = GLib::IOChannel.unix_new( e );
 
      @input.instance_variable_set("@channel", in_ch)
      @output.instance_variable_set("@channel", out_ch)
      @error.instance_variable_set("@channel", err_ch)
                
      f = Proc.new do |ch, cond, *o|
        case cond
        when GLib::IOCondition::HUP
          ch.unref
          output.instance_variable_set("@eof", true)
          next false
        end

        output.send :line_read, GLib::IOChannel.read_line(ch)[1]
        true
      end
    
      z = Proc.new do |ch, cond, *o|
        case cond
        when GLib::IOCondition::HUP
          ch.unref
          error.instance_variable_set("@eof", true)
          next false
        end

        error.send :line_read, GLib::IOChannel.read_line(ch)[1]
        true
      end
    
      GLib::io_add_watch( out_ch, GLib::IOCondition::IN | GLib::IOCondition::HUP, nil.to_ptr, &f);
      GLib::io_add_watch( err_ch, GLib::IOCondition::IN | GLib::IOCondition::HUP, nil.to_ptr, &z);
    
      GLib::child_watch_add pid do
        GLib::spawn_close_pid(pid)
      end
      
      return pid    
    end
  end
  
  # popen
  # 
  # @yieldparam [PBR::Popened] the Popened object
  # @return [Array]<PBR::Popened, Integer> the Popened object, and the childs PID
  def self.popen *argv, &b
    q = POpened.new
    b.call q
    pid = q.run *argv
    return q,pid
  end
  
  class Net
    class NoLIBSoupError < Exception
    end
    
    class Response
      attr_reader :headers
      
      def initialize msg
        @msg = msg
        @headers = {}
        h = Soup::MessageHeaders.wrap(msg.get_property("response-headers"))
        h.foreach do |q|
          @headers[q] = h.get_one(q) 
        end
      end
      
      def body
        body = Soup::MessageBody.wrap(@msg.get_property("response-body"))
        body = body.flatten.get_as_bytes.get_data().map do |b| b.chr end.join()
      end
    end
    
    def self.soup_session
      return @soup_session if @soup_session
      
      if ::Object.const_defined?(:Soup)
        @soup_session = Soup::Session.new
      else
        raise NoLIBSoupError.new("No namespace ::Soup")
      end
    end

    def self.request uri, mode = "GET", &b
      ss  = soup_session
      msg = Soup::Message.new(mode, uri)
      
      if b
        ss.queue_message msg do |s,m,*q|
          b.call(PBR::Net::Response.new(m))
        end
        
        return true
      
      else
        ss.send_message msg
        
        return PBR::Net::Response.new(msg)
      end
    end
  end

  # HTTP request. If block is given calls the block when the request is completed, otherwise blocks
  #
  # @param [String] uri
  # @param [Integer] mode
  #
  # @yieldparam [PBR::Net::Response]
  #
  # @return [PBR::Net::Response, nil]  
  def self.http_request uri, mode = "GET", &b
    PBR::Net.request uri, mode, &b
  end
  
  # Converts object +o+ into JSON string
  #
  # @param [::Object] o
  # @return [String] the serialized data
  def self.serialize o
    JSON.stringify o
  end
  
  # Parses a JSON string
  #
  # @param [String] str the data to parse
  # @return [::Object]
  def self.deserialize str
    JSON.parse str
  end   
end
