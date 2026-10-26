module DiskView
  class Window < Adw::ApplicationWindow
    include I18n
    @rows = Gtk::Box.new(:vertical, 10)
    @status = Gtk::Label.new("")
    @cancellable = Gio::Cancellable.new
    @closed = false
    @drive_rows = {} of String => Adw::ExpanderRow

    def initialize(app : Gtk::Application)
      super(application: app, title: "Disk View", default_width: 800, default_height: 540)
      set_size_request(700, 400)
      setup_actions(app)

      header = Adw::HeaderBar.new
      refresh = Gtk::Button.new_from_icon_name("view-refresh-symbolic")
      refresh.tooltip_text = translate("Refresh")
      refresh.action_name = "win.refresh"
      menu = Gtk::MenuButton.new
      menu.icon_name = "open-menu-symbolic"
      menu.primary = true
      menu.tooltip_text = translate("Main menu")
      model = Gio::Menu.new
      model.append(translate("Refresh"), "win.refresh")
      model.append(translate("About Disk View"), "win.about")
      model.append(translate("Close"), "win.close")
      menu.menu_model = model
      header.pack_end(menu)
      header.pack_end(refresh)

      content = Gtk::Box.new(:vertical, 10)
      content.margin_top = 12
      content.margin_bottom = 12
      content.margin_start = 16
      content.margin_end = 16
      content.append(label(translate("Drives & Partitions"), "title-2"))
      explanation = label(translate("Used space · refreshes automatically every 15 seconds"), "dim-label")
      explanation.wrap = true
      content.append(explanation)
      content.append(@rows)
      @status.xalign = 0.0
      @status.wrap = true
      @status.add_css_class("dim-label")
      @status.add_css_class("caption")
      content.append(@status)

      scroll = Gtk::ScrolledWindow.new
      scroll.hscrollbar_policy = :never
      scroll.child = content
      clamp = Adw::Clamp.new
      clamp.maximum_size = 1000
      clamp.child = scroll
      toolbar = Adw::ToolbarView.new
      toolbar.add_top_bar(header)
      toolbar.content = clamp
      self.content = toolbar

      close_request_signal.connect do
        @closed = true
        @cancellable.cancel
        false
      end
      GLib.timeout(15.seconds) do
        unless @closed
          reload
          true
        else
          false
        end
      end
      reload
    end

    private def setup_actions(app : Gtk::Application)
      refresh = Gio::SimpleAction.new("refresh", nil)
      refresh.activate_signal.connect { reload }
      add_action(refresh)
      about = Gio::SimpleAction.new("about", nil)
      about.activate_signal.connect { show_about }
      add_action(about)
      close = Gio::SimpleAction.new("close", nil)
      close.activate_signal.connect { self.close }
      add_action(close)
      app.set_accels_for_action("win.refresh", ["<Primary>r"])
      app.set_accels_for_action("win.about", ["F1"])
      app.set_accels_for_action("win.close", ["<Primary>w"])
    end

    private def show_about
      about = Adw::AboutDialog.new(
        application_name: "Disk View",
        application_icon: APP_ID,
        version: VERSION,
        developer_name: AUTHOR,
        developers: ["#{AUTHOR} <#{AUTHOR_EMAIL}>"],
        website: "https://github.com/magynhard/disk-view.cr",
        issue_url: "https://github.com/magynhard/disk-view.cr/issues",
        comments: translate("Drives, partitions and disk usage at a glance.\nBuilt with Crystal, GTK4 and libadwaita."),
        license_type: Gtk::License::MitX11,
        copyright: "© 2026 #{AUTHOR}"
      )
      about.present(self)
    end

    private def label(text : String, style : String? = nil) : Gtk::Label
      widget = Gtk::Label.new(text)
      widget.xalign = 0.0
      widget.add_css_class(style) if style
      widget
    end

    private def reload
      @cancellable.cancel
      @cancellable = Gio::Cancellable.new
      begin
        inventory = Disks.scan
        expanded = @drive_rows.transform_values(&.expanded?)
        @drive_rows.clear
        while child = @rows.first_child
          @rows.remove(child)
        end
        inventory.drives.each { |drive| add_drive(drive, @cancellable, expanded[drive.name]? || false) }
        unless inventory.other_filesystems.empty?
          @rows.append(label(translate("Other filesystems / Network"), "heading"))
          inventory.other_filesystems.each do |disk|
            group = Gtk::Box.new(:vertical, 0)
            add_filesystem(group, disk, @cancellable) { |_usage| }
            append_frame(group)
          end
        end
        count = inventory.drives.size
        @status.text = translate("%{drives} · Updated %{time}", drives: translate_count("%{count} drive", "%{count} drives", count), time: Time.local.to_s("%H:%M:%S"))
      rescue ex : File::Error
        @status.text = translate("Could not read drives: %{error}", error: ex.message || "")
      end
    end

    private def append_frame(child : Gtk::Widget)
      frame = Gtk::Frame.new(nil)
      frame.child = child
      @rows.append(frame)
    end

    private def usage_row(title : String, metadata : String, indented = false)
      box = Gtk::Box.new(:vertical, 5)
      box.margin_top = 10
      box.margin_bottom = 10
      box.margin_start = indented ? 32 : 12
      box.margin_end = 12

      line = Gtk::Box.new(:horizontal, 10)
      name = label(title, "heading")
      name.hexpand = true
      name.ellipsize = :end
      name.tooltip_text = title
      line.append(name)
      details = label(metadata, "dim-label")
      details.add_css_class("caption")
      line.append(details)
      box.append(line)

      bar = Gtk::ProgressBar.new
      box.append(bar)
      info = label(translate("Reading …"), "caption")
      info.wrap = true
      box.append(info)
      {box, bar, info}
    end

    private def set_bar(bar : Gtk::ProgressBar, fraction : Float64)
      bar.fraction = fraction
      if fraction >= 0.9
        bar.add_css_class("error")
      else
        bar.remove_css_class("error")
      end
    end

    private def add_drive(drive : Drive, cancellable : Gio::Cancellable, expanded : Bool)
      title = drive.model.empty? ? drive.name : "#{drive.name} · #{drive.model}"
      title += drive.rotational ? " · HDD" : " · SSD" unless drive.rotational.nil?
      filesystems = drive.filesystems.map { |disk| Disks.filesystem_name(disk.filesystem) }.reject(&.empty?).uniq
      title += " · " + filesystems.join(", ") unless filesystems.empty?
      title += " · #{drive.filesystems.first.paths.join(", ")}" unless drive.partitioned || drive.filesystems.first.paths.empty?
      row = Adw::ExpanderRow.new
      row.title = title
      row.use_markup = false
      row.subtitle_lines = 3
      row.title_lines = 1
      icon = drive.rotational == false ? "drive-harddisk-solidstate-symbolic" : "drive-harddisk-symbolic"
      row.add_prefix(Gtk::Image.new_from_icon_name(icon))
      bar = Gtk::ProgressBar.new
      bar.width_request = 90
      bar.valign = :center
      row.add_suffix(bar)
      @drive_rows[drive.name] = row
      usages = Array(Usage?).new(drive.filesystems.size, nil)
      update_summary(drive, usages, bar, row)

      drive.filesystems.each_with_index do |disk, index|
        if drive.partitioned
          partition = Gtk::Box.new(:vertical, 0)
          add_filesystem(partition, disk, cancellable, indented: true) do |usage|
            usages[index] = usage
            update_summary(drive, usages, bar, row)
          end
          row.add_row(partition)
        elsif disk.paths.empty?
          capacity = translate("%{size} total", size: DiskView.format_bytes(drive.capacity))
          status = translate("%{state} · Usage unknown", state: disk_status(disk))
          row.subtitle = "#{capacity}\n#{status}"
        else
          # A filesystem directly on a disk does not need a duplicate child row.
          query_usage(disk, cancellable) do |usage, error|
            usages[index] = usage
            update_summary(drive, usages, bar, row)
            row.tooltip_text = [disk.paths.join(", "), disk.filesystem, error, row.subtitle].reject(&.empty?).join(" · ")
          end
        end
      end
      row.enable_expansion = drive.partitioned
      row.expanded = expanded && drive.partitioned
      group = Adw::PreferencesGroup.new
      group.add(row)
      @rows.append(group)
    end

    private def update_summary(drive : Drive, usages : Array(Usage?), bar : Gtk::ProgressBar, row : Adw::ExpanderRow)
      summary = Summary.for_drive(drive, usages)
      set_bar(bar, summary.fraction)
      if summary.known_count == 0
        text = if drive.filesystems.all?(&.paths.empty?) && drive.filesystems.any? { |disk| disk.state.not_mounted? && !disk.filesystem.empty? }
                 translate("Not mounted · usage unavailable")
               else
                 translate("Usage unknown · no measurable filesystems")
               end
      else
        text = if summary.complete?
                 translate("%{size} used (%{percent} %%)", size: DiskView.format_bytes(summary.used), percent: (summary.fraction * 100).round(1))
               else
                 translate("At least %{size} used (%{percent} %%)", size: DiskView.format_bytes(summary.used), percent: (summary.fraction * 100).round(1))
               end
        text += "\n" + translate("%{size} available", size: DiskView.format_bytes(summary.available))
        text += " · " + translate("%{size} reserved", size: DiskView.format_bytes(summary.reserved)) if summary.reserved > 0
        text += " · " + translate("%{known}/%{total} measured", known: summary.known_count, total: summary.filesystem_count) unless summary.complete?
      end
      capacity = translate("%{size} total", size: DiskView.format_bytes(drive.capacity))
      row.subtitle = "#{capacity} · #{text}"
      tooltip = row.subtitle + "\n" + translate("Usage is relative to the full drive capacity. Unmounted or multi-device filesystems are excluded from the total. Unpartitioned space is not available filesystem space.")
      tooltip += "\n" + translate("Microsoft reserved partitions have no filesystem and are excluded from usage totals.") if drive.filesystems.any? { |disk| !disk.measurable? }
      row.tooltip_text = tooltip
      bar.tooltip_text = tooltip
    end

    private def add_filesystem(group : Gtk::Box, disk : Disk, cancellable : Gio::Cancellable, indented = false, &on_usage : Usage? ->)
      name = disk.source.starts_with?("/dev/") ? File.basename(disk.source) : disk.source
      role = partition_role(disk.metadata.role)
      description = [disk.metadata.label, role].reject(&.empty?).uniq.join(" · ")
      description = disk.metadata.partition_name if description.empty?
      title = [name, description, disk.paths.join(", ")].reject(&.empty?).join(" · ")
      metadata = [Disks.filesystem_name(disk.filesystem), disk.capacity.try { |bytes| DiskView.format_bytes(bytes) } || ""].reject(&.empty?).join(" · ")
      box, bar, info = usage_row(title, metadata, indented)
      box.tooltip_text = [title, disk.source, role, disk.metadata.partition_name, disk.metadata.partition_type].reject(&.empty?).uniq.join("\n")
      group.append(box)
      if disk.paths.empty?
        bar.visible = false
        info.text = if !disk.measurable?
                      translate("Reserved partition · no filesystem")
                    else
                      translate("%{state} · Usage unknown", state: disk_status(disk))
                    end
        info.tooltip_text = translate("Mount this filesystem to read its disk usage.") if disk.measurable? && disk.state.not_mounted?
        return
      end

      query_usage(disk, cancellable) do |usage, error|
        if usage
          set_bar(bar, usage.fraction)
          info.text = translate("%{size} used (%{percent} %%)", size: DiskView.format_bytes(usage.used), percent: (usage.fraction * 100).round(1))
          info.text += " · " + translate("%{size} available", size: DiskView.format_bytes(usage.available))
          info.text += " · " + translate("%{size} total", size: DiskView.format_bytes(usage.total)) unless disk.capacity
          info.text += " · " + translate("%{size} reserved", size: DiskView.format_bytes(usage.reserved)) if usage.reserved > 0
          size = translate("%{size} filesystem size", size: DiskView.format_bytes(usage.total))
          info.tooltip_text = "#{disk.source} · #{size}\n#{info.text}"
        else
          bar.visible = false
          info.text = translate("Usage unavailable")
          info.tooltip_text = error
        end
        on_usage.call(usage)
      end
    end

    private def disk_status(disk : Disk) : String
      case disk.state
      in .not_mounted?
        translate("Not mounted")
      in .mapped?
        translate("Used by %{devices}", devices: disk.holders.join(", "))
      in .swap?
        translate("Swap (active)")
      in .locked?
        translate("Encrypted (locked)")
      end
    end

    private def partition_role(role : PartitionRole) : String
      case role
      in .unknown?            then ""
      in .microsoft_reserved? then translate("Microsoft reserved (MSR)")
      in .microsoft_data?     then translate("Microsoft basic data")
      in .windows_recovery?   then translate("Windows recovery")
      in .efi_system?         then translate("EFI system partition")
      end
    end

    private def query_usage(disk : Disk, cancellable : Gio::Cancellable, &on_result : Usage?, String ->)
      file = Gio::File.new_for_path(disk.paths.first)
      file.query_filesystem_info_async("filesystem::size,filesystem::free,filesystem::used", 0, cancellable) do |_source, result|
        usage = nil
        error = ""
        begin
          attributes = file.query_filesystem_info_finish(result)
          next if cancellable.is_cancelled
          unless attributes.has_attribute("filesystem::size") && attributes.has_attribute("filesystem::free")
            raise translate("The filesystem does not report disk usage.")
          end
          total = attributes.attribute_uint64("filesystem::size")
          available = attributes.attribute_uint64("filesystem::free").clamp(0_u64, total)
          # GIO reports available space as free; used excludes reserved blocks.
          free = if attributes.has_attribute("filesystem::used")
                   total - attributes.attribute_uint64("filesystem::used").clamp(0_u64, total)
                 else
                   available
                 end
          usage = Usage.new(total, free, available)
        rescue ex
          next if cancellable.is_cancelled
          error = ex.message || translate("Could not read filesystem.")
        end
        on_result.call(usage, error)
      end
    end
  end
end
