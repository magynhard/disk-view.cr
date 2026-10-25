require "spec"
require "json"
require "../src/i18n"

private def with_language(language : String, locale : String, &)
  previous_language = ENV["LANGUAGE"]?
  previous_all = ENV["LC_ALL"]?
  previous_locale = String.new(LibC.setlocale(Gettext::LC::ALL, Pointer(LibC::Char).null))
  begin
    ENV["LC_ALL"] = locale
    ENV["LANGUAGE"] = language
    # Invalidate gettext caches between language changes in the test process.
    LibC.setlocale(Gettext::LC::ALL, "C")
    DiskView::I18n.setup(File.expand_path("../po", __DIR__))
    yield
  ensure
    if previous_language
      ENV["LANGUAGE"] = previous_language
    else
      ENV.delete("LANGUAGE")
    end
    if previous_all
      ENV["LC_ALL"] = previous_all
    else
      ENV.delete("LC_ALL")
    end
    LibC.setlocale(Gettext::LC::ALL, previous_locale)
  end
end

describe DiskView::I18n do
  # Do not require GTK, a display server, or any one specific system language.
  previous_locale = String.new(LibC.setlocale(Gettext::LC::ALL, Pointer(LibC::Char).null))
  test_locale = {"en_US.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "es_ES.UTF-8", "it_IT.UTF-8", "ru_RU.UTF-8", "pl_PL.UTF-8", "ko_KR.UTF-8", "ja_JP.UTF-8", "zh_CN.UTF-8"}.find do |candidate|
    !LibC.setlocale(Gettext::LC::ALL, candidate).null?
  end
  LibC.setlocale(Gettext::LC::ALL, previous_locale)

  if locale = test_locale
    expected_headings = {
      "de"    => "Laufwerke & Partitionen",
      "en"    => "Drives & Partitions",
      "fr"    => "Disques et partitions",
      "es"    => "Unidades y particiones",
      "zh_CN" => "驱动器与分区",
      "ru"    => "Накопители и разделы",
      "it"    => "Unità e partizioni",
      "pl"    => "Dyski i partycje",
      "ko"    => "드라이브 및 파티션",
      "ja"    => "ドライブとパーティション",
    }

    expected_headings.each do |language, heading|
      it "loads a complete #{language} catalog with intact formatting placeholders" do
        with_language(language, locale) do
          DiskView::I18n.translate("Drives & Partitions").should eq(heading)
          # Check every singular source message, including multiline messages,
          # so new UI text cannot silently remain untranslated in a catalog.
          source = File.read(File.expand_path("../src/window.cr", __DIR__))
          source.scan(/\btranslate\(("(?:[^"\\]|\\.)*")/).each do |match|
            message = String.from_json(match[1])
            translated = DiskView::I18n.translate(message)
            translated.scan(/%\{\w+\}/).map(&.[0]).sort.should eq(message.scan(/%\{\w+\}/).map(&.[0]).sort)
            translated.should_not eq(message) unless language == "en"
          end
          DiskView::I18n.translate("%{size} used (%{percent} %%)", size: "42 GiB", percent: 12.5).should contain("42 GiB")
          formatted = DiskView::I18n.translate("%{size} used (%{percent} %%)", size: "42 GiB", percent: 12.5)
          formatted.should contain("12.5 %")
          formatted.should_not contain("%%")
        end
      end
    end

    it "uses the correct Russian and Polish plural forms" do
      with_language("ru", locale) do
        {1 => "1 накопитель", 2 => "2 накопителя", 5 => "5 накопителей", 21 => "21 накопитель"}.each do |count, expected|
          DiskView::I18n.translate_count("%{count} drive", "%{count} drives", count).should eq(expected)
        end
      end
      with_language("pl", locale) do
        {1 => "1 dysk", 2 => "2 dyski", 5 => "5 dysków", 22 => "22 dyski"}.each do |count, expected|
          DiskView::I18n.translate_count("%{count} drive", "%{count} drives", count).should eq(expected)
        end
      end
    end

    it "honors the LANGUAGE priority list and falls back to English" do
      with_language("zz:fr:de", locale) do
        DiskView::I18n.translate("Refresh").should eq("Actualiser")
      end
      with_language("zz", locale) do
        DiskView::I18n.translate("Refresh").should eq("Refresh")
      end
    end
  else
    pending "translation catalog checks require an installed non-C UTF-8 locale" do
    end
  end

  it "uses English for the C locale even when LANGUAGE is set" do
    with_language("de", "C") do
      DiskView::I18n.translate("Refresh").should eq("Refresh")
    end
  end

  it "handles unavailable system locales without crashing" do
    with_language("de", "zz_INVALID.UTF-8") do
      DiskView::I18n.translate("Refresh").should eq("Refresh")
    end
  end
end
