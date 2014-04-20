path = File.join(File.dirname(__FILE__), 'mrblib')

begin
  Dir.mkdir path
rescue Errno::EEXIST
end

files = [
  "lib/pbr.rb",
  "lib/pbr/ui/pbr_ui.rb",
  "lib/pbr/rui/pbr_rui.rb",
  "lib/pbr/ui/gtk/pbr_uigtk.rb"
]

File.open(File.join(path, "pbr.rb"), "w") do |f|
  f.puts(files.map do |f|
    "# File: #{f}\n\n" + open(File.join(File.dirname(__FILE__), f)).read + "\n"
  end.join("\n"))
end
