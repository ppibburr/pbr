PBR::UI::Gtk::App.run(:title=>"Example") do |app|
  app.build do
    stack do
      label :text=>"Flows", :align=>:center, :expand=>false, :padding=>10
    
      flow :expand=>false do
        button(:label=>":expand=>true, :fill=>true")
        button(:label=>":expand=>true, :fill=>true")
        button(:label=>":expand=>true, :fill=>true")                
      end    
    
      flow :expand=>false do
        button(:label=>":expand=>true, :fill=>true")
        button(:label=>":expand=>true, :fill=>false", :fill=>false)
        button(:label=>":expand=>true, :fill=>true")                
      end
      
      flow :expand=>false do
        button(:label=>":expand=>true, :fill=>true")
        button(:label=>":expand=>false, :fill=>false", :expand=>false, :fill=>false)
        button(:label=>":expand=>true, :fill=>true")                
      end 
      
      flow :expand=>false do
        button(:label=>":expand=>false, :fill=>false", :expand=>false, :fill=>false)
        button(:label=>":expand=>false, :fill=>false", :expand=>false, :fill=>false)
        button(:label=>":expand=>false, :fill=>false", :expand=>false, :fill=>false)                
      end              
      
      label :text=>"Stacks", :expand=>false, :align=>:center,:padding=>10
      
      stack do
        button(:label=>":expand=>false, :fill=>false", :expand=>false, :fill=>false)
        button(:label=>":expand=>true, :fill=>false", :expand=>true, :fill=>false)
        button(:label=>":expand=>true, :fill=>true", :expand=>true, :fill=>true)  
      end
      
      toplevel.size = [800,400]
    end
  end
end 
