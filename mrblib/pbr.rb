# File: lib/pbr.rb

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


# File: lib/pbr/rui/pbr_rui.rb

# Similar to jquery/xui.js
module PBR::RUI
  TAG2CLASS = { 
  }
 
  [
    :Anchor,
    :Applet,
    :Area,
    :Media,
    :Base,
    :BaseFont,
    :Body,
    :Button,
    :Canvas,
    :Details,
    :Directory,
    :Div,
    :Embed,
    :FieldSet,
    :Font,
    :Form,
    :Frame,
    :FrameSet,
    :Head,
    :Heading,
    :Html,
    :IFrame,
    :Image,
    :Input,
    :Keygen,
    :Label,
    :Legend,
    :Link,
    :Map,
    :Marquee,
    :Menu,
    :Meta,
    :Mod,
    :Object,
    :OptGroup,
    :Option,
    :Paragraph,
    :Param,
    :Pre,
    :Quote,
    :Script,
    :Select,
    :Style,
    :TableCaption,
    :TableCell,
    :TableCol,
    :Table,
    :TableRow,
    :TableSection,
    :TextArea,
    :Title,
    :BR,
    :DList,
    :HR,
    :LI,
    :OList,
    :UList
  ].each do |q|
    TAG2CLASS["#{q}".upcase] = :"DOMHTML#{q}Element"
  end
  
  # An Array like object that eases mass DOM manipulation
  class Collection
    module Internal
      def get_length
        length
      end
      
      def item i
        self[i]
      end
    end
    
    include Enumerable
    include Internal
    
    attr_reader :view
    def initialize list=nil
      unless list
        list = []
        list.extend Collection::Internal
      end
      @list = list
    end
    
    def [] i
      @list.item(i)
    end
    
    def length
      @list.get_length
    end
    
    # Find all elements with a given attribute
    #
    # @param n [#to_s] attribute name
    #
    # @return [PBR::RUI::Collection]
    def has_attr?(n)
      find_all do |q|
        q.has_attribute n
      end
    end
    
    def find_all &b
      a = super
      a.extend Collection::Internal
      Collection.new(a)
    end
    
    # Find all elements with a given class
    #
    # @param c [#to_s] class name
    #
    # @return [PBR::RUI::Collection]
    def has_class?(c)
      find_all do |q|
        n=q.get_attribute("class").split(" ")
        n.index(c.to_s)
      end
    end
    
    # Adds a class name to all elements in the collection
    #
    # @param c [String] class name    
    def add_class c
      each do |q|
        str = q.get_attribute("class")

        if str.empty?
          str = c.to_s
        else
          str = str+" #{c}"
        end
    
        q.set_attribute("class",str)
      end
    end
    
    # Removes a class name from all elements in the collection
    #
    # @param c [String] class name
    def remove_class c
      each do |q|
        str = q.get_attribute("class")

        str = str.split(" ").find_all do |n|
          n != c.to_s
        end.join(" ")
      
        q.set_attribute("class",str)
      end
    end    
    
    def empty?
      length < 1
    end
    
    def map &b
      a = super
      a.extend self.class::Internal
      Collection.new(a)
    end
    
    # Get the parent elements of all elements on the collection
    #
    # @return [PBR::RUI::Collection]
    def parent
      map do |q|
        q.get_parent_element
      end
    end
    
    # Registers an EventListener on all elements in the collection
    #
    # @param evt [#to_s] event name
    # @param bool [Boolean]
    #
    # @yieldreturn [Boolean]
    def on evt, bool = false, &b
      each do |q|
        q.add_event_listener evt.to_s, bool, &b
      end
    
      return nil
    end
    
    # Emits an event on all elements in the collection. When a block is passed the Event being sent is yielded to allow for customization.
    #
    # @param evt [#to_s] event name
    # @param can_bubble [Boolean]
    # @param cancellable [Bollean]
    #
    # @yieldparam [WebKit::DOMEvent]
    def fire evt, can_bubble = true, cancellable = true, &b
      evt_type = "Event"
      
      types = {
        :focus     => "UIEvent",
        :blur      => "UIEvent",
        :keyup     => "KeyboardEvent",
        :keydown   => "KeyboardEvent",
        :click     => "MouseEvent",
        :mousedown => "MouseEvent",
        :mouseup   => "MouseEvent"
      }
      
      if h=types[evt.to_sym]
        evt_type = h
      end
      
      each do |q|
        e = q.get_owner_document.create_event(evt_type)
        
        if b
          b.call(e)
        end
        
        e.init_event evt.to_s, can_bubble, cancellable
        q.dispatch_event(e)
      end
      
      self
    end
    
    # @return [Array<String>] the tag names of all elements in the collection
    def tags
      a = []
      
      each do |q|
        a << q.get_tag_name
      end
      
      a
    end
    
    def each &b
      for x in 0..@list.get_length-1
        n = @list.item(x)
        if n.get_node_type == 1 and !n.is_a?(WebKit::DOMElement)
          n = WebKit::DOMElement.wrap(n.to_ptr)
          
          if cn=RUI::TAG2CLASS[n.get_tag_name]
            cls = ::WebKit::const_get(cn)
            n = cls.wrap n.to_ptr
          end
        end
        
        yield n
      end
      
      self
    end
    
    # Sets or Gets the innerHTML of all elements in the collection
    #
    # @param o [String, void]
    #
    # @return [Array<String>, void]
    def html *o
      if o.empty?
        a = []
        each do |e| a << e.get_inner_html end
        return(a)
      end
    
      each do |e| e.set_inner_html o[0] end
    end

    # Sets or Gets the innerText of all elements in the collection
    #
    # @param o [String, void]
    #
    # @return [Array<String>, void]
    def text *o
      if o.empty?
        a = []
        each do |e| a << e.get_inner_text end
        return(a)
      end
        
      each do |e| e.set_inner_text o[0] end
    end
  end

  # Intended to be included by a WebKit::DOMDocument
  module DOMDocument
    # Find elements by CSS selector
    #
    # @return [PBR::RUI::Collection]
    def query sel
      col = PBR::RUI::Collection.new(query_selector_all(sel))
      
      return col
    end
  end
  
  # Enhances a PBR::UI::Gtk::WebView
  module View
    # Loads an html string
    #
    # @param code [String] the html
    def render code
      native.load_html_string code, nil.to_ptr
      
      self
    end
    
    # Set the callback for when the view has finished loading a page. ! instance_exec
    def on_load &b
      native.signal_connect "load-finished" do
        instance_exec &b
      end
    end
    
    # @return [PBR::RUI::DOMDocument]
    def document
      d = native.get_main_frame.get_dom_document
      d.extend PBR::RUI::DOMDocument
      d
    end
    
    # Find elements by CSS selector
    #
    # @return [PBR::RUI::Collection]
    def query sel, &b
      collection = document.query sel
      
      collection.instance_exec(self, &b) if b
      
      return collection
    end
    
    # Execute javascript in the current page
    #
    # @param script [String] javascript code
    def execute script
      native.execute_script script
    end
    
    # Find elements by CSS selector in the current page
    #
    # @param selector [String] CSS selector
    # @return [PBR::RUI::Collection]
    def [] selector
      query selector
    end
    
    # Loads an html string
    #
    # @param html [String] html code
    def html= html
      native.load_html_string html, nil
    end
    
    # Get the HTML code of the current page
    #
    # @return [String] html code
    def html
      self["html"][0].get_outer_html
    end
    
    # Navigates to a location
    #
    # @param uri [String] the location to navigate to
    def location= uri
      native.open uri
    end 
    
    # @return [String] the current location
    def location
      native.get_uri
    end  
    
    # Alerts the user with a message
    #
    # @param msg [String] the message
    def alert msg
      document.get_default_view.alert(msg)
    end
    
    # Prompts the user for input
    #
    # @param msg [String] the message
    # @param val [String] the default value
    #
    # @return [String] the value entered
    def prompt msg, val=""
      document.get_default_view.prompt(msg, val)
    end  
    
    # Asks the user to confirm an action
    #
    # @param msg [String] the message
    #
    # @return [Boolean]
    def confirm msg
      document.get_default_view.confirm(msg)
    end             
  end
end


# File: lib/pbr/ui/pbr_ui.rb

module PBR
  # Skeleton for exposing a common, simple GUI interface
  module UI
    # Implemented by a 'frontend'
    module Backend
      def self.extended q
        app = Class.new(PBR::UI::App)
        
        app.define({:backend => q})
        
        q.const_set(:App, app)
      end
      
      # Initializes the backend library: ie, Gtk::init()
      def init
      
      end
      
      # Runs the Backend's 'main loop': ie, Gtk::main
      def main

      end
      
      # Exits the Backend's 'main loop': ie, Gtk::main_quit
      def quit

      end
    end
    
    class App
      def self.define config = {}
        @config = config
      end
      
      def self.backend
        @config[:backend]
      end
      
      def self.config
        @config
      end
      
      def self.inherited cls
        cls.singleton_class.define_method :inherited do |c|
          c.define cls.config 
        end
      end
    
      attr_reader :toplevel
      def initialize opts = {}
        
        @toplevel = window(opts)
        
        toplevel.on_delete do
          !at_exit()
        end
      end

      private
      
      def at_exit
        if !@on_quit_cb or !@on_quit_cb.call()
          self.class.backend.quit
        
          # never reaches here
          return true
        end
        
        return false
      end
    
      def append_widget widget, opts = {}
        if @build_mode
          if ivar = opts.delete(:id)
            instance_variable_set("@#{ivar}", widget)
          end
        end
      
        if opts[:scrolled]
          old  = widget
          
          q_opts = {:expand=>opts[:expand], :fill=>opts[:fill], :padding=>opts[:padding]}
          
          opts.delete(:expand)
          opts.delete(:fill)
          opts.delete(:padding)
          
          widget = scrolled(q_opts)
          widget.add old
          
          
          
          if @build_mode
            return
          end
        end      
      
        if @build_mode          
          if opts[:center]
            old  = widget
            
            q_opts = {:expand=>opts[:expand], :fill=>opts[:fill], :padding=>opts[:padding]}
            
            opts.delete(:expand)
            opts.delete(:fill)
            opts.delete(:padding)
            
            
            if @buildee.is_a?(PBR::UI::Stack)
              widget = flow(q_opts)
            end
            
            if @buildee.is_a?(PBR::UI::Flow)
              widget = stack(q_opts)
            end            
            
            build widget do
              append_widget(old, {:expand=>true, :fill=>false})             
            end
            
            if @build_mode
              return
            end
          end
        
          if @buildee.is_a?(PBR::UI::Box)
            layout = [opts[:expand] == nil ? true : !!opts[:expand], opts[:fill] == nil ? true : !!opts[:fill], opts[:padding] == nil ? 0 : opts[:padding]]
            @buildee.add widget, *layout
          else
            @buildee.add widget
          end
        end
      end      
      
      def create_widget type, opts = {}
        @last = widget = self.class.backend::const_get(type).new(opts) 
        
        widget.send :set_application, self
        
        return widget     
      end
      
      def create_append type, opts={}
        widget = create_widget(type, opts)
        
        append_widget(widget, opts)
        
        return widget
      end
      
      def create_append_build type, opts={}, &b
        widget = create_append(type, opts)
        
        if b
          build(widget, &b)
        end
        
        return widget   
      end
      
      public
      
      def last
        @last
      end
      
      def this
        @buildee
      end
      
      # Quits the 'main' loop.
      def quit
        self.class.backend.quit
      end
      
      # Allows for 'Builder' style
      #
      # @param [Container] buildee the current container being appended to, defaults to 'toplevel'
      # @param b [Proc]  instance_exec(&b) is performed
      #
      # @return [::Object] the result of performing +b+
      def build buildee = toplevel, &b
        pm                = @build_mode
        @build_mode       = true
        pb                = @buildee
        @buildee          = buildee
        
        r = instance_exec &b
      
        @build_mode = pm
        @buildee    = pb
      
        return r
      end
      
      # Adds a listener to perform when the user attempts to exit the application
      #
      # @yieldreturn [Boolean] true to prevent exiting, false to allow
      def on_quit &b
        @on_quit_cb = b
      end
    
      # Create a [Window]
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [Window] as 'root' container
      #
      # @return [PBR::UI::Window]
      def window title=nil, opts = {}, &b
        create_append_build :Window, opts, &b
      end
      
      # Create a [PBR::UI::Button]
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [Button] as 'root' container
      #
      # @return [PBR::UI::Button]      
      def button opts = {}, &b
        create_append_build :Button, opts, &b
      end

      # Create a [Notebook]
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [Notebook] as 'root' container
      #
      # @return [PBR::UI::Notebook]      
      def notebook opts={}, &b
        create_append_build :Notebook, opts, &b
      end
      
      # Create the proper descendant of [PBR::UI::Book::Page] for the [Book] type
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [PBR::UI::Book::Page] as 'root' container
      #
      # @return [PBR::UI::Book::Page]      
      def page opts={}, &b
        type = nil
        
        if @buildee.is_a?(PBR::UI::Book)
          type = @buildee.class
        else
          type = opts[:type]
        end
        
        raise "No Page Type resolved!" unless type
      
        book = @buildee.is_a?(PBR::UI::Book) ? @buildee : opts[:book]
      
        flw = type::Page.new(book, opts)
        
        append_widget(flw, opts)
        
        if b
          build(flw, &b)
        end
        
        flw
      end      
      
      # Create a [Flow]
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [Flow] as 'root' container
      #
      # @return [PBR::UI::Flow]      
      def flow opts={}, &b
        create_append_build :Flow, opts, &b
      end
      
      # Create a [Stack]
      #
      # @param [Hash] opts options, where options maybe any property name and its value
      # @param [Proc] b when a block is passed App#build() is performed with this [Stack] as 'root' container
      #
      # @return [PBR::UI::Stack]       
      def stack opts={}, &b
        create_append_build :Stack, opts, &b
      end   
      
      # Create a ScrolledView
      #
      # @return [PBR::UI::ScrolledView]
      def scrolled opts={}, &b
        create_append_build :ScrolledView, opts, &b
      end         
      
      # Creates a Menubar
      #
      # @return [PBR::UI::Menubar]
      def menubar opts={}, &b
        create_append_build :Menubar, opts, &b
      end      
      
      # Create a MenuItem
      #
      # @return [PBR::UI::MenuItem]
      def menu_item opts={}, &b
        create_append_build :MenuItem, opts, &b
      end 
      
      # Create a Menu
      #
      # @return [PBR::UI::Menu]
      def menu opts={}, &b
        create_append_build :Menu, opts, &b
      end           
      
      # Create a Toolbar
      #
      # @return [PBR::UI::Toolbar]
      def toolbar opts={}, &b
        create_append_build :Toolbar, opts, &b
      end       
      
      # Create a ToolItem
      #
      # @return [PBR::UI::ToolItem]
      def tool_item opts={}, &b
        create_append_build :ToolItem, opts, &b
      end       
         
      # Create a ToolButton
      #
      # @return [PBR::UI::ToolButton]
      def tool_button opts={}, &b
        create_append_build :ToolButton, opts, &b
      end       
         
      # Create a SeparatorToolItem
      #
      # @return [PBR::UI::SeparatorToolItem]               
      def tool_separator opts={}, &b
        create_append :SeparatorToolItem, opts
      end      
      
      
      def html opts={}, &b
        create_append :HtmlView, opts
      end
      
      # TODO: Gtk specific
      def web_view opts={}, &b
        create_append :WebView, opts
      end
      
      # Create a Entry widget
      #
      # @return [PBR::UI::Entry]
      def entry opts={}, &b
        create_append :Entry, opts
      end 
      
      # Creates a widget rendering an image on screen
      #
      # @return [PBR::UI::Image]
      def image opts={}, &b
        create_append :Image, opts
      end 
      
      def hrule opts={}, &b
        create_append :HRule, opts
      end  
      
      def vrule opts={}, &b
        create_append :VRule, opts
      end              
      
      # Creates a Spinner
      #
      # @return [PBR::UI::Spinner]
      def spinner opts={}, &b
        create_append :Spinner, opts
      end       
      
      # Creates a ListBox
      #
      # @return [PBR::UI::ListBox]
      def list_box opts={}, &b
        create_append :ListBox, opts
      end 
      
      # Creates a TextView
      #
      # @return [PBR::UI::TextView]
      def text opts={}, &b
        create_append :TextView, opts
      end             
      
      # Create a Label
      #
      # @return [PBR::UI::Label]
      def label opts={}, &b
        create_append :Label, opts
      end                                
      
      # Display the main window
      def display
        
      end
      
      # @return [void]
      def alert title="", body="", value="" 
      end       
      
      # @return [Boolean]
      def confirm title="", body=""
      end       
      
      # @return [String] or nil
      def prompt title="", body="", value="" 
      end     
    
      # Called around the time of 'main'
      def on_run &b
      
      end
    
      # Setup an [App] and call +b+ then run the application
      #
      # @param [String] title the application's main [Window]'s title
      # @param [Hash] opts options, where options may be any of [Window]'s properties with values
      #
      # @yieldparam [App] self
      def self.run(opts = {}, &b)
        backend.init
        
        ins = new(opts)
        b.call(ins)
        ins.display
        
        backend.main
      end
    end
  
    class KeyEvent
      # @return [Integer]
      def keyval
      end
      
      # @return [Symbol] :key_press or :key_release
      def type
      end
      
      # @return [Integer] mask of modifiers present
      def state
      end
      
      # @return [Boolean] true if the Ctrl key is pressed
      def ctrl?
      end
      
      # @return [Boolean] true if the Shift key is pressed      
      def shift?
      end
      
      # @return [Boolean] true if the Alt key is pressed      
      def alt?
      end
    end
  
    # UI entry class
    class Widget   
      def self.native_class
        @native_class
      end
    
      def self.define native_class, config = {:constructor => :new, :defaults => {}}
        setup native_class, config
      end
      
      def self.setup native_class, config
        @native_class = native_class
        @config = config
      end
      
      attr_reader :native
      def initialize opts={},&b
        @native = self.class.constructor(self,opts,&b)
        
        modify opts
      end
      
      # Modify's widgets properties from values in +opts+
      #
      # @param opts [Hash] options
      def modify opts={}
        opts.each_key do |k|
          if (k.to_s.split("_")[0] == "on") and !respond_to?(:"#{k}=")
            send k do |*o|
              @_application.send opts[k], *o
            end
            next
          end
          
          send :"#{k}=", opts[k] if respond_to?(:"#{k}=")
        end
      end
      
      def sensitive= bool
      end
      
      def sensitive?
      end
      
      # Sets the text to display after the user hovers the mouse over for a length of time
      #
      # @param txt [String] the text to display
      def tooltip= txt
        
      end
      
      # Displays the widget
      def show

      end
      
      # Displays the widget and all its descendants
      def show_all
      
      end
      
      # Hides the widget
      def hide
      
      end
      
      # @return [Array<Integer>] representing [width, height] repsectively
      def size
      
      end
      
      # @param b [Proc] the callback to call on key-press
      #
      # @yieldparam [PBR::UI::KeyEvent] e
      #
      # @yieldreturn [Boolean] true to prevent continuation, otherwise false      
      def on_key_down &b
      
      end
      
      # @param b [Proc] the callback to call on key-release
      #
      # @yieldparam [PBR::UI::KeyEvent] e
      #
      # @yieldreturn [Boolean] true to prevent continuation, otherwise false
      def on_key_up &b
      
      end
      
      def on_mouse_down &b
      
      end
      
      def on_mouse_up &b
      
      end
          
      # Creates the underlying native 'widget'      
      def self.constructor wrapper, *o, &b
      
      end
      
      # @return [PBR::UI::Container] containing the widget
      def container
        @_container
      end
      
      private
      def set_container container
        @_container = container
      end
      
      def set_application app
        @_application = app
      end
    end
    
    module Container
      # Add a widget to a [Container]
      #
      # @param widget [PBR::UI::Widget]
      def add widget
        widget.send :set_container, self
      end
      
      # Remove a widget from a [Container]
      #
      # @param widget [PBR::UI::Widget]      
      def remove widget
      
      end
    end
    
    # Toplevel Window which may contain other widgets
    class Window < Widget
      include Container
      
      def initialize opts={},&b
        super
        if opts[:size]
          self.default_size = opts[:size]
        end
      end
    
      # The size the [Window] should initialy be
      #
      # @param [Array<Integer>] size the size, [width, height]
      def default_size= size 
      
      end
    
      # Sets the [Window]'s title
      #
      # @param [String] title
      def title= title
        
      end
      
      # @return [String] the title
      def title
      
      end
      
      # Resize the window
      #
      # @param [Array<Integer>] size [width, height]
      def size= size

      end      
      
      # Adds a handler for when the user attempts to exit the window
      #
      # @yieldreturn [Boolean] true to prevent exiting, false to allow
      def on_delete &b
      
      end
    end
    
    class Button < PBR::UI::Widget
      # @return [String] the label text    
      def label
      
      end
      
      # Sets the [Button]'s label
      #
      # @param [String] txt the label text
      def label= txt
        
      end
      
      # Adds a handler for 'click' events
      def on_click &b
      
      end
    end
    
    # Base class of BoxLayout [Container]'s
    class Box < Widget
      include Container
      
      # Adds a [Widget]
      #
      # @param [Widget] widget the [Widget] to add
      # @param [Boolean] expand when true the widget can react to the +fill+ parameter
      # @param [Boolean] fill when true, if expand is true, then the widget will grow to fill the allotted space. When false, the widget will center in the allotted space
      # @param [Integer] pad the amount of padding to place ahead and after the widget
      def add widget, expand=true, fill=true, pad = 0
        
      end
    end
    
    # A Box that will layout it's children horizontally. The X-axis shall be refered to as the major-axis
    class Flow < PBR::UI::Box
    end
    
    # A Box that will layout it's children vertically. The Y-axis shall be refered to as the major-axis    
    class Stack < PBR::UI::Box
    end 
    
    
    # A Widget that displays a string of text
    class Label < Widget
      # The current text value
      #
      # @return [String]
      def text
      
      end
      
      # Set the text to display
      #
      # @param txt [String]
      def text= txt
      
      end
    end
    
    # A Widget that renders a list of items
    class ListBox < Widget
      # @param a [Array<String>] the items to display
      def items= a
      
      end
      
      # @return [Array<::Object>]
      def items
      end
      
      # @return [Integer] the current selection
      def selection
      end
      
      # Sets the selected item
      #
      # @param i [Integer] the item to select
      def select i
      end
   
      # Activates an item
      #
      # @param i [Integer] the item to activate
      def select i
      end      
      
      # Select the next item
      def select_next; end
      
      # Select the previous item
      def select_before; end
      
      # Callback for when an item is activated
      def on_item_activate &b; end
      
      # Callback for when an item is selected
      def on_item_selected &b; end
    end
    
    class ListView < Widget
    end
    
    class ComboBox < Widget
      def choices= v
        @choices = v
      end
      
      def choices
        @choices
      end
      
      def value
        
      end
      
      def value= i
        
      end
    end
    
    # A Widget the allows numeric input via keyboard as well as the mouse
    class Spinner < Widget
      # @return [Float] the value
      def value; end
      
      # Sets the +value+
      #
      # @param val [Float] the value to set. Must be between #min and #max
      def value= val; end
      
      # @return [Float] the minimum value
      def min; end
      
      # @return [Float] the maximum value
      def max; end
      
      def min= min; end
      def max= max; end
      
      # @return [Float]
      def step; end
      
      # @param amt [Float] the amount to increment by when the adjustment arrows are pressed
      def step= amt; end
      
      def digits; end
      
      # @param digits [Integer] the amount of decimal places
      def digits= amt; end
      
      # Set the callback for when value-changed
      #
      # @yieldparam v [Float] the value
      def on_change &b 
      end
    end
    
    class Rule < Widget;
    end
    
    # A Widget displaying a horizontal line
    class HRule < Rule
    end
    
    # A Widget displaying a vertical line    
    class VRule < Rule
    end
    
    class Scale < Widget
    end
    
    class HScale < Scale
    end
    
    class VScale < Scale
    end
    
    class Toolbar < Widget
      include Container
    end
    
    class ToolItem < Widget
      include Container
    end
    
    class SeparatorToolItem < ToolItem    
    end
    
    class ToolButton < ToolItem
      # Retrieve the image widget
      #
      # @return [PBR::UI::Image]
      def image
      
      end
      
      # @return [String] the label text
      def label
      
      end
      
      # Sets the label text
      # @param txt [String]
      def label= txt; end
      
      def on_click &b
      
      end
    end
    
    # A Menubar
    class Menubar < Widget
      include Container
    end
    
    # A Menu
    class Menu < Widget
      include Container   
    end
    
    # A MenuItem
    class MenuItem < Widget
      include Container
      
      # @param txt [String] the label
      def label= txt
      end
      
      def label
      end
      
      def image= q
      end
      
      def on_activate &b
      end
    end
    
    # A widget the allows a single-line of editable text
    class Entry < Widget
      # Sets the text value
      #
      # @param txt [String]
      def text= txt
      
      end
      
      # @return [String] the text value
      def text
      
      end
     
      # @param b [Proc] called when the user presses the enter key
      def on_activate &b
      
      end
    end
    
    class Frame < Widget
      include Container
    end
    
    # A Widget the allows for scrolling of its child
    class ScrolledView < Widget
      include Container
    end
    
    class TextView < Widget
      def text
      
      end
      
      def text= txt
      
      end
      
      def src= src
    
      end
      
      def undo
      
      end
      
      def redo
      
      end
      
      def cut
      
      end
      
      def copy
      
      end
      
      def paste
      
      end
      
      def delete
      
      end    
      
      def bold
      
      end
      
      def underline
      
      end
      
      def italic
      
      end
      
      def strikethrough
      
      end
      
      def indent
      
      end
      
      def outdent
      
      end
      
      def unmodified= bool
      end
    
      def modified?
      end      
    
      def on_modify &b
        @on_modify_cb = b
      end
      
      def on_unmodify &b
        @on_unmodify_cb = b
      end      
      
      def on_toggle_modify &b
        @on_toggle_modify_cb = b
      end
      
      def on_source_load &b
        @source_loaded_cb = b
      end
      
      private
      def source_loaded
        @source_loaded_cb.call(self) if @source_loaded_cb
      end
      
      def unmodified
        cb = @on_toggle_modify_cb
        cb.call(self) if cb      
      
        cb = @on_unmodify_cb
        cb.call(self) if cb
      end      
      
      def modified
        cb = @on_toggle_modify_cb
        cb.call(self) if cb      
      
        cb = @on_modify_cb
        cb.call(self) if cb
      end
    end
    
    module IconSize
      MENU        = 'menu'
      BUTTON      = 'button'
      TOOLBAR     = 'toolbar'
      TOOLBAR_BIG = 'toolbar_big'
      LARGE       = 'large'
    end
    
    # Widget rendering a image to the screen
    class Image < Widget
      def src
        @src
      end
      
      def theme= theme
      end
      
      def theme
      end
      
      def file
        @file
      end
    
      # Sets the contents from a URI
      #
      # @param src [String] an URI
      def src= src
        @file = nil
        @src  = src
      end
      
      # Sets the contents from a path
      #
      # @param file [String] the path
      def file= file
        @src  = nil
        @file = file
      end
      
      # @param size [Array<Integer>] [width, height]
      def size= size
      
      end
      
      # @return [Array<Integer>] [width, height]
      def size
        
      end
      
      # @return [Integer] the width
      def width
        size[0]
      end
      
      # @return [Integer] the height    
      def height
        size[1]
      end
      
      # Sets the height
      #
      # @param h [Integer]
      def height= h
        size= [width, h]
      end
      
      # Sets the width
      #
      # @param w [Integer]
      def width= w
        size= [w, height]
      end     
      
      def on_source_load &b
        @on_src_load_cb = b
      end
      
      private
      def source_loaded
        if cb=@init_src_cb
          cb.call(self)
          
          @init_src_cb = nil
        end
      
        if cb=@on_src_load_cb
          cb.call(self)
        end
      end
    end
    
    # A Widget that allows paging of multiple views
    class Book < Widget
      include Container
      
      # A page of a Book
      class Page < Widget
        include Container
        
        attr_reader :book
        def initialize book, opts={}
          @book = book
          super opts
        end
      end
      
      # The current page
      def page; end
      
      # sets the current page to display
      def page= i;end
      
      # @param b [Proc] Callback called when page has changed
      def on_page_changed &b
      
      end
      
      # @param b [Proc] Callback called when user has attempted to close the page
      # 
      # @yieldreturn [Boolean] true to prevent closing, false otherwise    
      def on_close &b
        @on_close_cb = b
      end
      
      private
      
      def nice_child widget
        unless widget.is_a?(self.class::Page)
          pg = self.class::Page.new(self)
          pg.add widget
      
        else
          pg = widget
        end  
        
        return pg    
      end
      
      def closed_button_pressed pg
        if cb=@on_close_cb
          unless cb.call(pg)
            remove(pg)
          end
        else
          remove(pg)
        end
      end  
    end
    
    # A Book implementation where a row of 'tabs' allow the user to select the page to display
    class Notebook < Book
      class Page < Book::Page
        # Sets the 'tab' label
        #
        # @param txt [String] the label
        def label= txt; end
        
        # @return [String] the label
        def label; end
        
        # @param opts [Hash, nil] when hash, image#modify(opts) is performed
        #
        # @return [::Object] a PBR::UI::Image when no value is passed
        def image opts=nil
        
        end
      end
    end
    
    class Canvas < Widget
    end
    
    # A Widget that renders HTML code
    class HtmlView < Widget
      # @param html [String] html code
      def load html
      end
      
      # @param html [String] html code      
      def html= html
      end
    end
    
    class WebView < Widget
      include PBR::RUI::View        
    end
  end
end


# File: lib/pbr/ui/gtk/pbr_uigtk.rb

module PBR::UI::Gtk
  extend PBR::UI::Backend
  
  ###
  def self.init
    ::Gtk.init 0,nil
  end
    
  def self.main
    ::Gtk.main
  end
    
  def self.quit
    ::Gtk.main_quit
  end
  ###
  
  class App
    def display
      GLib::Idle::add 200 do
        cb = @on_run_cb
        cb.call if cb
        
        false
      end
    
      toplevel.show_all
    end
    
    def on_run &b
      @on_run_cb = b
    end
    
    def alert title="", body=""
      g = Gtk::MessageDialog.new(toplevel.native, ::Gtk::DialogFlags::DESTROY_WITH_PARENT, ::Gtk::MessageType::INFO, ::Gtk::ButtonsType::CLOSE)
      vb = g.get_message_area
      g.set_title "PBR-UI Message"
      i = -1
      vb.foreach do |q|
        i += 1
        if i == 0
          q.set_markup "<big><b>#{title}</b></big>" 
          
        elsif i == 1
          q.set_label body
          q.show
        end
      end
      
      g.run
      g.destroy
    end
    
    def confirm title="", body=""
      g = Gtk::MessageDialog.new(toplevel.native, ::Gtk::DialogFlags::DESTROY_WITH_PARENT, ::Gtk::MessageType::WARNING, ::Gtk::ButtonsType::CANCEL | ::Gtk::ButtonsType::OK)

      vb = g.get_message_area
      
      i = -1
      vb.foreach do |q|
        i += 1
        if i == 0
          q.set_markup "<big><b>#{title}</b></big>" 
          
        elsif i == 1
          q.set_label body
          q.show
        end
      end

      response = g.run
      
      g.destroy
      
      case response
      when ::Gtk::ResponseType::OK
        return true
      else
        return false
      end
    end
    
    def prompt title="", body="", value=""
      g = Gtk::MessageDialog.new(toplevel.native, ::Gtk::DialogFlags::DESTROY_WITH_PARENT, ::Gtk::MessageType::QUESTION, ::Gtk::ButtonsType::OK_CANCEL)
      
      vb = g.get_message_area      
      
      i = -1
      vb.foreach do |q|
        i += 1
        if i == 0
          q.set_markup "<big><b>#{title}</b></big>" 
          
        elsif i == 1
          q.set_label body
          q.show
        end
      end

      e = PBR::UI::Gtk::Entry.new
      e.text=value
      e.show
      
      e.on_activate do
        g.response(::Gtk::ResponseType::OK)
      end
      
      
      g.get_message_area.pack_start e.native, false, false, 2
      
      response = g.run
      
      val = e.text
      
      g.destroy
      
      case response
      when ::Gtk::ResponseType::OK
        return val
      else
        return nil
      end
    end    
  end

  class KeyEvent < PBR::UI::KeyEvent
    def initialize event
      @native = event
    end
    
    def state
      @native[:state]
    end
    
    def type
      case @native[:type]
      when Gdk::EventType::KEY_PRESS
        :key_press
      when Gdk::EventType::KEY_RELEASE
        :key_release
      end
    end

    def keyval
      @native[:keyval]
    end
    
    def press?
      case type
      when :key_press
        return true
      end
      
      return false
    end
    
    def release?
      case type
      when :key_release
        return true
      end
      
      return false
    end    
    
    def ctrl?
      (state & ::Gtk::accelerator_get_default_mod_mask) == ::Gdk::ModifierType::CONTROL_MASK
    end
    
    def alt?
      (state & ::Gtk::accelerator_get_default_mod_mask) == ::Gdk::ModifierType::MOD1_MASK
    end
    
    def shift?
      (state & ::Gtk::accelerator_get_default_mod_mask) == ::Gdk::ModifierType::SHIFT_MASK
    end   
    
    def modifiers?
      state != 0
    end     
  end

  module Widget
    def sensitive?
      native.get_sensitive
    end
    
    def sensitive= bool
      native.set_sensitive !!bool
    end
  
    def tooltip= txt
      native.set_tooltip_text txt
    end
    
    def show
      native.show
    end
    
    def show_all
      native.show_all
    end
    
    def hide
      native.hide
    end
    
    def size
      return native.get_allocated_width, native.get_allocated_height
    end
    
    def on_key_up &b
      native.signal_connect "key-release-event" do |*o|
        b.call PBR::UI::Gtk::KeyEvent.new(o[0].get_struct)
      end
    end
    
    def on_key_down &b
      native.signal_connect "key-press-event" do |*o|
        b.call PBR::UI::Gtk::KeyEvent.new(o[0].get_struct)
      end
    end    
  end

  module Container
    def add widget
      widget.send :set_container, self
    
      native.add widget.native
    end
    
    def remove widget
      native.remove widget.native
    end
  end

  class Window < PBR::UI::Window
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
      
    define Gtk::Window
    
    def self.constructor wrapper, *o, &b
      ::Gtk::Window.new(0)
    end
    
    def default_size= size
      native.set_default_size *size
    end
    
    def title= title
      native.set_title title
    end
    
    def title
      native.get_title
    end
    
    def size
      native.get_size
    end
    
    def size= size
      native.resize *size
    end
    
    def on_delete &b
      native.signal_connect "delete-event" do
        b.call
      end
    end
  end
  
  module Box
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
          
    def add widget, expand=true, fill=true, pad=0
      p pad
      native.pack_start widget.native, expand, fill, pad
    end
  end
  
  class Flow < PBR::UI::Flow
    include PBR::UI::Gtk::Box
    
    def self.constructor wrapped, opts={},&b
      same_major_size = !!opts[:same_major_size]
      spacing         = opts[:spacing] ||= 0  
            
      ::Gtk::HBox.new same_major_size, spacing
    end
  end
  
  module Rule
    include PBR::UI::Gtk::Widget
  end
  
  class HRule < PBR::UI::HRule
    include Rule
    
    def self.constructor *o
      ::Gtk::HSeparator.new
    end
  end
  
  class VRule < PBR::UI::VRule
    include Rule
    
    def self.constructor *o
      ::Gtk::VSeparator.new
    end    
  end  
  
  module MenuShell
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container    
    
    def add widget
      native.append widget.native
    end
  end
  
  class Menubar < PBR::UI::Menubar
    include PBR::UI::Gtk::MenuShell
    
    def self.constructor *o
      ::Gtk::MenuBar.new
    end
  end
  
  class Menu < PBR::UI::Menu
    include PBR::UI::Gtk::MenuShell
    
    def self.constructor *o
      ::Gtk::Menu.new
    end    
  end
  
  class MenuItem < PBR::UI::MenuItem
    include Widget
    include Container
  
    def self.constructor *o
      ::Gtk::MenuItem.new
    end
    
    def label 
      native.get_label
    end
    
    def label= txt
      native.set_label txt.to_s
    end
    
    def add widget
      native.set_submenu widget.native
    end
    
    def on_activate &b
      native.signal_connect "activate" do
        b.call self
      end
    end
  end
   
  class Stack < PBR::UI::Stack
    include PBR::UI::Gtk::Box
    
    def self.constructor wrapped, opts={},&b
      same_major_size = !!opts[:same_major_size]
      spacing         = opts[:spacing] ||= 0  
            
      ::Gtk::VBox.new same_major_size, spacing
    end
  end  
  
  class Button < PBR::UI::Button
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
    
    def self.constructor *o
      n = ::Gtk::Button.new
    end
    
    def initialize opts={}
      label = opts.delete :label
      theme = opts.delete :theme
      
      super opts
      
      p theme,:LABEL
      
      @image = theme ? PBR::UI::Gtk::Image.new(:theme=>theme) : PBR::UI::Gtk::Image.new(:size=>[12,12])
      @label = PBR::UI::Gtk::Label.new(:text=>label)

      add @hb = PBR::UI::Gtk::Flow.new
      
      @hb.add @image,true,true if theme and !label
      @hb.add @image,false,false if theme and label      
      @hb.add @label,true,true if label or !theme
      
      @show_image = true if theme
      @show_label = true if label
      
      @image.native.ref
      @label.native.ref
    end
    
    def image *o
      if o.empty?
        return @image
      end
      
      @hb.remove @image
      @hb.remove @label
      
      if @show_label
        @hb.add @image, false,false
        @hb.add @label,true,true
      else
        @hb.add @image, true, true
      end
      
      @show_image = true
      
      @image.modify o[0]
    end
    
    def label
      return unless @label
      @label.text
    end
    
    def label= txt
      if @show_image
        @hb.remove @image
        @hb.remove @label
        
        @show_label = nil
        
        @hb.add @image, false,false
      end
      
      @hb.add @label, true, true if !@show_label
      
      @show_label = true
      
      @label.text = txt
    end
    
    def on_click &b
      native.signal_connect "clicked" do
        b.call
      end
    end
  end
  
  class ListBox < PBR::UI::ListBox
    include PBR::UI::Gtk::Widget
    include PBR::RUI::View
    
    def self.constructor *o
      v = ::WebKit::WebView.new
      v.load_html_string self.html, ""
      
      v.signal_connect "load-finished" do
        o[0].query("body").on :click do |*a|
          target = WebKit::DOMElement.wrap(a[1].get_target)
          
          list = [target]
          list.extend PBR::RUI::Collection::Internal
          
          col = PBR::RUI::Collection.new(list)
          
          next if ["HTML", "BODY"].index(col.tags[0])
          
          until !col.has_class?("item").empty?
            col = col.parent
          end

          o[0].query(".selected").remove_class("selected")

          col.add_class("selected")
          
          
          o[0].send :select_item, o[0].selection
        end
        
        o[0]["body"].on :keyup do |*a|
          evt = a[1]
          case evt.get_key_code
          when 40
            o[0].select_next
          when 38
            o[0].select_before
          when 13
            o[0].send :activate_item, o[0].selection
          end
        end
        
        o[0].send :init
      end
      v
    end
    
    def self.html
      "
<html>
  <head>
    #{style}
  </head>
  <body>
  </body>
</html>    
      "
    end
    
    def self.style
      "
        <style>
          html {width:100%;}
          
          body { margin:0px 0px 0px 0px; padding:0px 0px 0px 0px; height:100%; min-height:100%; }
          
          .item {
            min-height:20px;
            max-height:20px;
            margin-left:2px;
          }
          
          .selected {
            background-color:blue;
          }
        </style>
      "
    end
    
    def select_next
      if self[".selected"].empty?
        select 0
        
      else
      
        col = self[".item"]
        sel = col.has_class?("selected")[0]
        i = col.to_a.map do |q| q.to_ptr.address end.index(sel.to_ptr.address)
        select i+1
      end
    end
    
    def select i
      col = self[".item"]
    
      i = col.length-1 if i > col.length-1
      i = 0 if i < 0

      list = [col[i]]
      list.extend PBR::RUI::Collection::Internal

      n = PBR::RUI::Collection.new(list)
      n.fire :click
    end
    
    def select_before
      if self[".selected"].empty?
        select 0
        
      else
        col = self[".item"]
        sel = col.has_class?("selected")[0]
        i = col.to_a.map do |q| q.to_ptr.address end.index(sel.to_ptr.address)
        select i-1
      end
    end
    
    def items= a
      init_cb = proc do
        code = a.map do |q|
          "<div class=item tabindex=0>#{q}</div>"
        end.join("\n")
      
        query("body").html code
      end
      
      if @init
        init_cb.call
      else
        @init_cb = init_cb
      end  
    end
    
    def items
      self[".item"].text
    end
    
    def selection
      col = self[".item"]
      sel = col.has_class?("selected")[0]
      
      return unless sel
      
      i = col.to_a.map do |q| q.to_ptr.address end.index(sel.to_ptr.address)
    end
    
    def on_item_activate &b
      @on_item_activate_cb = b
    end
    
    def on_item_selected &b
      @on_item_selected_cb = b
    end    
    
    private
    
    def init
      return if @init
      cb = @init_cb
      if cb
        cb.call
      end
      @init = true
    end
    
    def select_item i
      cb = @on_item_selected_cb
      if cb
        cb.call i
      end
    end
    
    def activate_item i
      return unless i
      
      return if i < 0
      return if i > self[".item"].length-1
    
      if selection != i
        select i
      end
    
      cb = @on_item_activate_cb
      if cb
        cb.call i
      end
    end  
  end
  
  class Spinner < PBR::UI::Spinner
    include PBR::UI::Gtk::Widget
    
    def self.constructor *o
      ::Gtk::SpinButton.new_with_range 0, 1, 1
    end
    
    def step= amt
      native.set_increments amt.to_f, 10.0
    end
    
    def min= val
      native.set_range val.to_f, native.get_range[1]
    end
    
    def max= val
      native.set_range native.get_range[0], val.to_f
    end    
    
    def min
      native.get_range[0]
    end
    
    def max
      native.get_range[1]
    end    
    
    def digits= amt
      native.set_digits amt
    end
    
    def digits
      native.get_digits
    end
    
    def value= val
      native.set_value val.to_f
    end
    
    def value
      native.get_value
    end
    
    def on_change &b
      native.signal_connect "value-changed" do
        b.call value
      end
    end
  end
  
  class ScrolledView < PBR::UI::ScrolledView
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
        
    def self.constructor *o
      ::Gtk::ScrolledWindow.new
    end
  end
  
  class Label < PBR::UI::Label
    include PBR::UI::Gtk::Widget
    
    def self.constructor wrapped, opts={}, &b
      opts[:align] ||= :left
      
      ::Gtk::Label.new
    end
    
    def align= pos
      case pos
      when :left
        native.set_alignment 0.0,0.5
      when :center
        native.set_alignment 0.5,0.5
      when :right
        native.set_alignment 1.0,0.5
      else
        raise "Unknown value for 'pos' argument to 'align='"
      end
    end
    
    def text= txt
      native.set_markup txt
    end
    
    def text
      native.get_text
    end
  end  
  
  class Entry < PBR::UI::Entry
    include PBR::UI::Gtk::Widget
    
    def self.constructor wrapped, opts={}, &b
      ::Gtk::Entry.new
    end
    
    def text
      native.get_text
    end
    
    def text= txt
      native.set_text txt
    end
    
    def on_activate &b
      native.signal_connect "activate" do
        b.call self
      end
    end
  end
  
  class Toolbar < PBR::UI::Toolbar
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
  
    def self.constructor *o
      n = ::Gtk::Toolbar.new
      n
    end
    
    def add widget
      native.insert widget.native, -1
    end
  end
  
  class ToolItem < PBR::UI::ToolItem
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
    
    def self.constructor *o
      ::Gtk::ToolItem.new()
    end    
  end

  class SeparatorToolItem < PBR::UI::SeparatorToolItem
    include PBR::UI::Gtk::Widget
    
    def self.constructor *o
      n=::Gtk::SeparatorToolItem.new()
    end  
  end
  
  class ToolButton < PBR::UI::ToolButton
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
    
    def self.constructor *o
      n=::Gtk::ToolButton.new()
    end
    
    def initialize opts={}
      i_opts = {:size=>[24,24]}
      
      i_opts[:file]  = opts.delete(:file) if opts[:file]
      i_opts[:src]   = opts.delete(:src) if opts[:src]
      i_opts[:size]  = opts.delete(:size) if opts[:size]      
      i_opts[:theme] = opts.delete(:theme) if opts[:theme]   
      i_opts.delete(:size) if i_opts[:theme]
      
      super opts
      
      @image = PBR::UI::Gtk::Image.new(i_opts)
      
      native.set_icon_widget @image.native
    end
    
    def image o=nil
      unless o
        return @image
      end
      
      if o.is_a?(Hash)
        @image.modify(o)
      end
      
      return true
    end
    
    def label
      native.get_label    
    end
    
    def label= txt
      native.set_label txt
    end
    
    def on_click &b
      native.signal_connect "clicked" do
        b.call()
      end
    end
  end  
  
  def self.get_icon_theme widget
    name, size = widget.native.get_icon_name(FFI::MemoryPointer.new(:pointer))
    prepend = case size
    when ::Gtk::IconSize::MENU
      PBR::UI::IconSize::MENU
    when ::Gtk::IconSize::BUTTON
      PBR::UI::IconSize::BUTTON
    when ::Gtk::IconSize::SMALL_TOOLBAR
      PBR::UI::IconSize::TOOLBAR
    when ::Gtk::IconSize::LARGE_TOOLBAR
      PBR::UI::IconSize::TOOLBAR_BIG
    when ::Gtk::IconSize::DIALOG
      PBR::UI::IconSize::LARGE                     
    end
    
    return prepend+"-"+name  
  end
  
  def self.icon_from_theme theme
    raw  = theme.split("-")
    size = raw.shift
    name = raw.join("-")
    
    native_size = case size
    when PBR::UI::IconSize::MENU
      ::Gtk::IconSize::MENU
    when PBR::UI::IconSize::LARGE
      ::Gtk::IconSize::DIALOG
    when PBR::UI::IconSize::TOOLBAR
      ::Gtk::IconSize::SMALL_TOOLBAR
    when PBR::UI::IconSize::TOOLBAR_BIG
      ::Gtk::IconSize::LARGE_TOOLBAR
    when PBR::UI::IconSize::BUTTON
      ::Gtk::IconSize::BUTTON                 
    end
    
    return name, native_size    
  end
  
  class Image < PBR::UI::Image
    include PBR::UI::Gtk::Widget
    
    def self.constructor *o,&b
      ::Gtk::Image.new
    end
    
    def initialize opts={}
      o = opts
      opts = {}
      
      super opts
      
      unless o[:theme]
        native.set_from_pixbuf ::GdkPixbuf::Pixbuf.new(nil.to_ptr, false, 8, *(o[:size] ? o[:size] : [0,0]))
      else
        self.theme = o[:theme]
      end
      
      o.each_pair do |k,v|
        send :"#{k}=", v
      end
    end
    
    def theme
      PBR::UI::Gtk::get_icon_theme self
    end
    
    def theme= theme
      name, size = PBR::UI::Gtk::icon_from_theme(theme)
      native.set_from_icon_name name,size
    end
    
    def src= src
      super
      
      PBR::http_request src do |resp|
        l = GdkPixbuf::PixbufLoader.new
        l.set_size *size
        l.write(q=resp.body, q.length)
        
        native.set_from_pixbuf(l.get_pixbuf)
        
        source_loaded()
      end
    end
    
    def file= file
      super
      o = size
      native.set_from_pixbuf(GdkPixbuf::Pixbuf.new_from_file_at_size(file, *size))
      self.size = o
      
      self
    end
    
    def size= size
      b = native.get_pixbuf.scale_simple(size[0], size[1], Gdk::INTERP_BILINEAR)
      native.set_from_pixbuf b
      
      size
    end
    
    def size
      [native.get_pixbuf.get_width, native.get_pixbuf.get_height]
    end
    
    def width
      size[0]
    end
    
    def height
      size[1]
    end
    
    def height= h
      super native.get_pixbuf.get_height
    end
    
    def width= w
      super native.get_pixbuf.get_height
    end    
  end
  
  module Book
    include PBR::UI::Gtk::Widget
    include PBR::UI::Gtk::Container
      
    module Page
      include PBR::UI::Gtk::Widget
      include PBR::UI::Gtk::Container
        
      def self.included q
        def q.constructor wrapped, opts={}, &b
          ::Gtk::Frame.new
        end
      end
    end
    
    def self.included q
      def q.constructor *o,&b
        ::Gtk::Notebook.new
      end
    end
    
    def add widget
      pg = nice_child(widget)
      
      native.append_page(pg.native, pg.send(:get_tab))
      
      return pg
    end
    
    def page
      native.get_current_page
    end
    
    def page= pg
      native.set_current_page pg
    end
    
    def on_page_changed &b
      native.signal_connect "switch-page" do
        b.call
      end
    end    
  end
  
  class Notebook < PBR::UI::Notebook
    include PBR::UI::Gtk::Book
    
    class Page < PBR::UI::Notebook::Page
      include PBR::UI::Gtk::Book::Page
    
      class Tab < PBR::UI::Gtk::Flow
        
        attr_reader :label,:close,:image
        def initialize opts={}
          super
          
          add @image = PBR::UI::Gtk::Image.new(:size=>[24,24])
          add @label = PBR::UI::Gtk::Label.new
          add @close = PBR::UI::Gtk::Button.new(:label=>"x")
          
          @close.native.set_relief ::Gtk::ReliefStyle::NONE
          
          show_all
          
          image.hide
        end
      end
      
      def initialize book, opts={}
        l = opts[:label]
        opts.delete(:label)
        
        super book,opts
        
        @tab = self.class::Tab.new()
        
        @tab.close.on_click do
          @book.closed_button_pressed self
        end
        
        if l
          self.label= l
        end
      end
      
      def label= txt
        @tab.label.text= txt
      end
      
      def image opts=nil
        @tab.image.show
      
        unless opts
          @tab.image
        else
          @tab.image.hide if opts.delete(:hidden)
        
          @tab.image.modify opts
        end
      end
      
      private
      def get_tab
        @tab.native
      end
    end 
  end
  
  class ComboBox < PBR::UI::ComboBox
    include PBR::UI::Gtk::Widget
    
    def self.constructor wrapped, opts={}, &b
      ::Gtk::ComboBox.new
    end  
  end
  
  class HtmlView < PBR::UI::HtmlView
    include PBR::UI::Gtk::Widget
    
    def self.constructor wrapped, opts={}, &b
      WebKit::WebView.new
    end
    
    def load html
      native.load_html_string html, ""
    end
    
    def html= html
      load(html)
    end
  end
  
  class TextView < PBR::UI::TextView
    include PBR::UI::Gtk::Widget
  
    def self.constructor wrapper, *o
      n = ::WebKit::WebView.new
      
      n.signal_connect "load-finished" do
      document = n.get_main_frame.get_dom_document
        e=n.get_main_frame.get_dom_document.get_element_by_id("internal")
        e.focus
        wrapper.send :init
        e.add_event_listener "input", true do
          if wrapper.send :check_modify
            wrapper.send :modified
          else
            wrapper.send :unmodified
          end

          sel         = document.get_default_view.get_selection();
          prior_range = sel.get_range_at(0)

          # updates undo/redo
          wrapper.internal.blur
          wrapper.internal.focus
          
          # restore cursor
          range = document.create_range();
          range.set_start(prior_range.get_end_container, prior_range.get_end_offset);
          range.collapse(true);
          sel.remove_all_ranges();
          sel.add_range(range);

          true
        end
      end
      
      n.load_html_string "<html><head><style>
body, html {margin:0; padding:0; min-height: 100%;}
</style></head><body height=100%><div style='height:100%;' id=internal tabindex=0 contenteditable=true></div><div id=selection style='display: none;'></div></body></html>'", ""
      n
    end
    
    def initialize opts={}
      super({})
      
      @on_init = proc do
        p opts
        modify(opts)
      end
    end
    
    def text
      internal.get_inner_text
    end
    
    def text= txt
      internal.set_inner_text txt
    end
    
    def undo
      cmd :undo
    end
    
    def redo
      cmd :redo
    end
    
    def font_size= size
      cmd :FontSize, size
    end
    
    def cut
      cmd :cut
    end
    
    def copy
      cmd :copy
    end
    
    def paste
      cmd :paste
    end
    
    def delete
      cmd :delete
    end    
    
    def bold
      cmd :bold 
    end
    
    def underline
      cmd :underline
    end
    
    def italic
      cmd :italic
    end
    
    def strikethrough
      cmd :strikethrough
    end
    
    def indent
      cmd :indent
    end
    
    def outdent
      cmd :outdent
    end
    
    def selection
      native.execute_script("t = document.getSelection(); document.getElementById('selection').innerText=t;")
      document.get_element_by_id('selection').get_inner_text
    end    
    
    def insert pos, txt
      set_caret pos
      code = "
function pasteHtmlAtCaret(html) {
    var sel, range;
    if (window.getSelection) {
        // IE9 and non-IE
        sel = window.getSelection();
        if (sel.getRangeAt && sel.rangeCount) {
            range = sel.getRangeAt(0);
            range.deleteContents();

            // Range.createContextualFragment() would be useful here but is
            // only relatively recently standardized and is not supported in
            // some browsers (IE9, for one)
            var el = document.createElement(\"div\");
            el.innerHTML = html;
            var frag = document.createDocumentFragment(), node, lastNode;
            while ( (node = el.firstChild) ) {
                lastNode = frag.appendChild(node);
            }
" + "
            range.insertNode(frag);

            // Preserve the selection
            if (lastNode) {
                range = range.cloneRange();
                range.setStartAfter(lastNode);
                range.collapse(true);
                sel.removeAllRanges();
                sel.addRange(range);
            }
        }
    } else if (document.selection && document.selection.type != \"Control\") {
        // IE < 9
        document.selection.createRange().pasteHTML(html);
    }
}
" + <<EOC
pasteHtmlAtCaret("#{txt}");
EOC

      native.execute_script code
    end
    
    def prepend txt
      insert 0, txt
    end
    
    def append_txt
    
    end
    
    def unmodified= bool
      if bool
        @save = internal.get_inner_html
      end
    end
    
    def modified?
      check_modify
    end
    
    def src= src
      PBR::http_request src do |resp|
        self.text = resp.body
        source_loaded
      end
    end
    
    private
    
    def set_caret pos
code=<<EOC
var el = document.getElementById("internal");
var range = document.createRange();
var sel = window.getSelection();
range.setStart(el, #{pos});
range.collapse(true);
sel.removeAllRanges();
sel.addRange(range);
EOC

      native.execute_script code
    end
    
    def cmd q, val=""
      internal.get_owner_document.exec_command "#{q}", true, val.to_s
    end
    
    def document
      native.get_main_frame.get_dom_document
    end
    
    def internal
      native.get_main_frame.get_dom_document.get_element_by_id("internal")
    end
    
    def check_modify
      bool = (@save != internal.get_inner_html)

      return bool
    end    
    
    def init
      if cb=@on_init
        cb.call
      end
    end
  end
  
  class WebView < PBR::UI::WebView
    include PBR::UI::Gtk::Widget 
    
    def self.constructor wrapped, opts={}, &b
      WebKit::WebView.new
    end
  end  
end

