PBR::UI::Gtk::App.run(:title=>"Example", :default_size=>[400,400]) do |app|
  app.build do
    button(:label=>"Quit").on_click do
      quit()
    end
  end
end 
