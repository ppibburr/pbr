PBR::UI::Gtk::App.run do |app|
  app.build do
    stack do
      entry :fill=>false, :theme=>"menu-help-about"  
      entry :fill=>false, :icon_position=>:right ,:theme=>"menu-edit-clear" 
    end
  end
end
