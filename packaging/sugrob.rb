# Homebrew cask for a personal tap, e.g. github.com/Olzhiro4ka/homebrew-tap as Casks/sugrob.rb:
#   brew install --cask olzhiro4ka/tap/sugrob
# After each release, bump `version` and set `sha256` from the release's .sha256 file.
cask "sugrob" do
  version "0.1.0"
  sha256 :no_check # replace with the Sugrob-#{version}.dmg checksum

  url "https://github.com/Olzhiro4ka/Snow/releases/download/v#{version}/Sugrob-#{version}.dmg"
  name "Sugrob"
  desc "Snow that settles on your windows and Dock, with no permissions and no network"
  homepage "https://github.com/Olzhiro4ka/Snow"

  depends_on macos: ">= :sonoma"

  app "Sugrob.app"

  uninstall quit: "io.github.olzhiro4ka.sugrob"

  zap trash: "~/Library/Preferences/io.github.olzhiro4ka.sugrob.plist"

  caveats <<~EOS
    Sugrob is not notarized unless the release notes say so. If macOS refuses to open it:
      xattr -dr com.apple.quarantine #{appdir}/Sugrob.app
  EOS
end
