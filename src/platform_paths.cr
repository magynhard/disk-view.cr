module DiskView::PlatformPaths
  HOST_ROOT = "/run/host/root"

  def self.sandboxed? : Bool
    File.file?("/.flatpak-info")
  end

  # Flatpak's host-root permission provides the host's mount namespace here.
  # Keep displayed paths unchanged and translate only paths used for I/O.
  # Mount points from mountinfo are kernel-resolved paths; do not call realpath
  # on arbitrary host paths (absolute symlinks would escape into the sandbox).
  def self.host_path(path : String, sandboxed = sandboxed?) : String
    raise ArgumentError.new("Expected an absolute host path") unless path.starts_with?('/') && !path.split('/').includes?("..")
    sandboxed ? HOST_ROOT + path : path
  end

  def self.mountinfo(sandboxed = sandboxed?) : String
    sandboxed ? HOST_ROOT + "/proc/1/mountinfo" : "/proc/self/mountinfo"
  end
end
