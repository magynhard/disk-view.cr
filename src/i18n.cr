require "gettext"

module DiskView::I18n
  extend self

  DOMAIN = "de.magynhard.DiskView"

  def setup(locale_dir : String = default_locale_dir) : Nil
    # The shard's setlocale wrapper assumes success; libc can return NULL when
    # the requested system locale is not installed.
    if LibC.setlocale(Gettext::LC::ALL, "").null?
      LibC.setlocale(Gettext::LC::ALL, "C")
    end
    Gettext.bindtextdomain(DOMAIN, locale_dir)
    Gettext.bind_textdomain_codeset(DOMAIN, "UTF-8")
  end

  def default_locale_dir : String
    executable_dir = File.dirname(Process.executable_path || PROGRAM_NAME)
    installed = File.expand_path("../share/locale", executable_dir)
    return installed if File.file?(File.join(installed, "en", "LC_MESSAGES", "#{DOMAIN}.mo"))
    development = File.expand_path("../po", executable_dir)
    return development if Dir.exists?(development)
    File.expand_path("../po", __DIR__)
  end

  def translate(message : String, **values) : String
    translated = Gettext.dgettext(DOMAIN, message)
    values.empty? ? translated : translated % values
  end

  def translate_count(singular : String, plural : String, count : Int32) : String
    Gettext.dngettext(DOMAIN, singular, plural, count.to_u32) % {count: count}
  end
end
