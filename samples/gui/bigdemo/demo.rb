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
end


App.run(:title=>"Example") do |app|
  app.build do
    stack do
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
          end
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
