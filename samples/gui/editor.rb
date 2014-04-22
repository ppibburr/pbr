class Editor < PBR::UI::Gtk::App
  def write
    unless @path
      @path = prompt "Save File As:", "Enter a path to save to."
      
      @path = @path.empty? ? nil : @path
    end
    
    return unless @path
    
    PBR.write @path, @editor.text
    
    return true
  end
  
  def open_file
    @path = prompt "Open File:", "Enter a path to open."
      
    @path = @path.empty? ? nil : @path
    
    return unless @path
    
    @editor.text = PBR.read(@path)
  end
end

Editor.run "Editor" do |app|
  app.build do
    stack do
      toolbar :expand => false do
        tool_button(:theme=>"button-document-open").on_click do
          open_file()
        end
        
        tool_button(:theme=>"button-document-save", :id=>:save).on_click do
          next unless write()
        
          @editor.unmodified= true
          @save.sensitive=false
          @editor_content_state.text = "Content modified? <span foreground='blue'>#{@editor.modified?}</span>"          
        end            
        
        tool_button(:theme=>"button-edit-undo").on_click do
          @editor.undo
        end
        
        tool_button(:theme=>"button-edit-redo").on_click do
          @editor.redo
        end                                  
      end
      
      debounce = false      
      text(:scrolled=>true, :id=>:editor).on_toggle_modify do   
        bool = @editor.modified?
        
        next unless debounce == !bool
        
        debounce = !debounce
        
        @save.sensitive= bool
  
        @editor_content_state.text = "Content modified? <span foreground='blue'>#{@editor.modified?}</span>"
      end
      
      label :text=>"Content modified? <span foreground='blue'>true</span>", :id=>:editor_content_state, :expand => false
    end  
    
    toplevel.size=[400,400]
  end
end
