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
