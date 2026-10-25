module DiskView
  APP_ID  = "de.magynhard.DiskView"
  AUTHOR  = "Matthäus J. N. Beyrle"
  VERSION = {{read_file("#{__DIR__}/../shard.yml").split("version: ")[1].split("\n")[0]}}

  # Embed the icon so the executable also works outside the source directory.
  RESOURCE_DATA = {{read_file("#{__DIR__}/../data/disk-view.gresource")}}
  RESOURCE      = Gio::Resource.new_from_data(GLib::Bytes.new(RESOURCE_DATA.to_unsafe, RESOURCE_DATA.bytesize))
end
