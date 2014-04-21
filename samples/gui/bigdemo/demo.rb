class App < PBR::UI::Gtk::App
  def report_key_event e
    report_event 'KeyEvent: type, '+e.type.to_s+', keyval, '+e.keyval.to_s
    false
  end
  
  def report_event msg
    @events.prepend(msg+'<br>')
    false
  end
  
  def item_activated *o
    report_event 'ListBox#on_item_activate: '+o[0].to_s
  end
  
  def about
    alert("PBR-UI: Big Demo", "Emulates a large application with complex layouts and events")
  end
end


App.run(:title=>"Example") do |app|
  app.build do
    stack do
      toolbar do
        tool_button :theme=>"toolbar-application-exit"
        tool_button :theme=>"toolbar-help-about", :on_click=>:about        
      end
    
      label(:text=>"Welcome to the bigdemo", :expand=>false)
      
      notebook do
        page :label=> "ListBox" do
          list_box(:items=>["Apples","Oranges","Pears","Bannanas"], :on_item_activate=>:item_activated).on_item_selected do |v|
            report_event("ListBox#on_item_selected: #{v}")
          end
        end
        
        page :label=>"Labels" do
          stack do
            label :text=>":align=>:left", :expand=>false
            label :text=>":align=>:center", :expand=>false, :align=>:center
            label :text=>":align=>:right", :expand=>false, :align=>:right
            label :text=>":text =><big>Big</big> <b>bold</b><span foreground='blue'>blue</span> label"                        
          end
      
          this.image :theme=>"menu-help-about"
        end
        
        page :label=>"Text" do
          stack do
            flow :expand => false do
              button(:theme=>"button-edit-undo").on_click do
                @editor.undo
              end
              
              button(:theme=>"button-edit-redo").on_click do
                @editor.redo
              end
              
              button(:theme=>"button-format-text-bold").on_click do
                @editor.bold
              end
              
              button(:theme=>"button-format-text-italic").on_click do
                @editor.italic
              end
              
              button(:theme=>"button-format-text-underline").on_click do
                @editor.underline
              end                        
            end
            
            text :scrolled=>true, :id=>:editor
          end
          
          this.image :theme=>"menu-text-x-generic"
        end        
      end
      
      label(:align=>:center, :expand=>false).modify :text=>"Misc events"
      
      text(:id=>:events, :scrolled=>true,:font_size=>"5")
    end
    
    toplevel.size = [400,400]
    
    toplevel.on_key_down do |e|
      report_key_event(e)
    end
    
    toplevel.on_key_up do |e|
      report_key_event(e)
    end
  end
end 
