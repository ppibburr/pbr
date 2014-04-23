# Six (6) lines less than './longer.rb'

PBR::UI::Gtk::App.run "Menus" do |app|
  app.build do
    stack do
      menubar(:expand=>false) do |mb|
        mb.item(:label=>"_File") do |m|
          m.item(:label=>"_Quit", :theme=>"menu-application-exit").on_activate do quit end
        end
        
        mb.item(:label=>"_Extra") do |m|
          m.item(:label=>"Foo").menu do |sub|
            sub.item(:label=>"Bar", :theme=>"menu-help-about")
          end
          
          m.item(:label=>"Toggle Something", :type=>:check, :checked=>true)         
        end
      end
    end
  
    toplevel.size=[400,400]
  end
end
