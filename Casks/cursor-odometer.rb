cask "cursor-odometer" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/Shmoopi/cursor-odometer/releases/download/v#{version}/CursorOdometer-v#{version}.zip",
      verified: "github.com/Shmoopi/cursor-odometer/"
  name "Cursor Odometer"
  desc "Menu-bar utility that measures physical mouse cursor travel distance"
  homepage "https://github.com/Shmoopi/cursor-odometer"

  depends_on macos: ">= :sonoma"

  app "CursorOdometer.app"

  zap trash: [
    "~/Library/Application Support/net.shmoopi.cursorodometer",
    "~/Library/Caches/net.shmoopi.cursorodometer",
    "~/Library/Preferences/net.shmoopi.cursorodometer.plist",
    "~/Library/Saved Application State/net.shmoopi.cursorodometer.savedState",
  ]
end
