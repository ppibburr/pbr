PBR::UI::Gtk::App.run "Menus" do |app|
  app.build do
    stack do
      menubar :expand=>false do
        menu_item :label=>:"_File" do
          menu do
            menu_item(:label=>"_Quit").on_activate do
              quit()
            end
          end
        end
        
        menu_item :label=>:"_Help" do
          menu do
            menu_item(:label=>"_About").on_activate do
              alert("About PBR-UI","This is a sample program demonstrating menus.")
            end
          end
        end        
      end
    end
  
  
    toplevel.size=[400,400]
  end
end
