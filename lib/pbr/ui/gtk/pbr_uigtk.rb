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
    
    def prompt_path opts={}
      opts[:type]  ||= PBR::UI::ChoosePathAction::OPEN
      opts[:title] ||= "Select a location ..."
      
      
      action = nil
      case opts[:type]
      when PBR::UI::ChoosePathAction::FOLDER;
        action = ::Gtk::FileChooserAction::SELECT_FOLDER
      when PBR::UI::ChoosePathAction::SAVE
        action = ::Gtk::FileChooserAction::SAVE
      when PBR::UI::ChoosePathAction::OPEN
        action = ::Gtk::FileChooserAction::OPEN
      end
      
      dialog = Gtk::FileChooserDialog.new(opts[:title],
                                            nil,
                                            action,
                                            )
                                           
      dialog.set_current_folder(opts[:folder]) if opts[:folder]     
      dialog.set_filename(opts[:path]) if opts[:path]
      dialog.set_current_name(opts[:name]) if opts[:name]                                     
                                            
      result = nil
      case dialog.run
      when Gtk::ResponseType::ACCEPT
        result = dialog.get_filename
      end

      dialog.destroy

      return nil unless result
      
      return result
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
      i=::Gtk::MenuItem.new
      i.set_use_underline true
      i
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
        
        debounce = false
        e.add_event_listener "input", true do
          if wrapper.send :check_modify
            wrapper.send :modified unless debounce
            debounce = true            
          else
            wrapper.send :unmodified
            debounce = false
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
