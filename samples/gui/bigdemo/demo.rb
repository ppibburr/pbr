PBR::UI::Gtk::App.run(:title=>"Example") do |app|
  app.build do
    stack do
      label(:text=>"Welcome to the bigdemo", :expand=>false)
      
      notebook do
        page :label=> "Page One" do
          list_box :items=>["Apples","Oranges","Pears","Bannanas"]
        end
      end
      
      label(:align=>:center, :expand=>false).modify :text=>"This entry has a handler for when the user types the enter key."
      
      entry(:expand=>false)
    end
    
    toplevel.size = [400,400]
  end
end 
