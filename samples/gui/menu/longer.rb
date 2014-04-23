# Six (6) lines more than './shorter.rb'

PBR::UI::Gtk::App.run "Menus" do |app|
  app.build do
    stack do
      menubar :expand=>false do
        menu_item :label=>:"_File" do
          menu do
            menu_item(:label=>"_Quit" ,:theme=>"menu-application-exit").on_activate do quit end
          end
        end
        
        menu_item :label=>:"_Extra" do
          menu do
            menu_item(:label=>"_Foo", :theme=>"menu-help-about") do
              menu() do
                menu_item :label=>"Bar"
              end
            end
            
            menu_item :type=>:check, :label=>"Toggle Something", :checked=>true
          end
        end        
      end
    end
  
    toplevel.size=[400,400]
  end
end
