echo "Installing Dependencies"
brew install --cask sf-symbols
brew install jq
brew install gh
brew tap FelixKratz/formulae
brew install sketchybar
curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v1.0.23/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf
cp -r $HOME/.config/sketchybar $HOME/.config/sketchybar_backup
# remove the old folder
rm -rf $HOME/.config/sketchybar
# create symlink for sketchybar folder
ln -s $HOME/.dotfiles/sketchybar $HOME/.config/sketchybar
# remove the symlink after a few seconds to prevent it from being used
brew services restart sketchybar