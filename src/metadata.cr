module DiskView
  APP_ID       = I18n::DOMAIN
  AUTHOR       = "Matthäus J. N. Beyrle"
  AUTHOR_EMAIL = "disk-view.github.com@mail.magynhard.de"
  VERSION      = {{read_file("#{__DIR__}/../shard.yml").split("version: ")[1].split("\n")[0]}}

  # Embed the icon so the executable also works outside the source directory.
  RESOURCE_DATA = {{read_file("#{__DIR__}/../data/disk-view.gresource")}}
  RESOURCE      = Gio::Resource.new_from_data(GLib::Bytes.new(RESOURCE_DATA.to_unsafe, RESOURCE_DATA.bytesize))
end
