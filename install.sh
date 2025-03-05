#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create symlinks for dotfiles
create_symlinks() {
    echo "Creating symlinks for dotfiles..."
    for file in "$HOME/.dotfiles/dotfiles/"*.symlink; do
        if [ -f "$file" ]; then
            filename=$(basename "$file" .symlink)
            target="$HOME/.$filename"
            
            # Backup existing file if it's not a symlink
            if [ -f "$target" ] && [ ! -L "$target" ]; then
                echo "Backing up existing $target to $target.backup"
                mv "$target" "$target.backup"
            fi
            
            # Create symlink
            echo "Creating symlink: $target -> $file"
            ln -sf "$file" "$target"
        fi
    done
}

# Function to manage services
manage_services() {
    if command_exists brew; then
        echo "Setting up yabai and skhd services..."
        
        # Install yabai and skhd if not already installed
        if ! command_exists yabai; then
            echo "Installing yabai..."
            brew install koekeishiya/formulae/yabai
        fi
        
        if ! command_exists skhd; then
            echo "Installing skhd..."
            brew install koekeishiya/formulae/skhd
        fi
        
        # Stop services if they're running
        echo "Stopping services if running..."
        yabai --stop-service 2>/dev/null
        skhd --stop-service 2>/dev/null
        
        # Start services
        echo "Starting yabai and skhd services..."
        yabai --start-service
        skhd --start-service
        
        echo "Services started. Note: you might need to allow accessibility permissions"
        echo "System Preferences -> Security & Privacy -> Privacy -> Accessibility"
    else
        echo "Homebrew not found. Please install yabai and skhd manually."
    fi
}

package_to_install="
    tmux
    tree
    wget
    zsh
    curl
    git
    eza
    zoxide
    iterm2
    zsh-autosuggestions
    zsh-syntax-highlighting
"

# Function to install packages based on the package manager
install_packages() {
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y zsh curl git
        # Install eza for debian/ubuntu
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/TheLocehiliosan/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo apt-get update
        sudo apt-get install -y eza
        # Install zoxide
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    elif command_exists yum; then
        sudo yum update
        sudo yum install -y zsh curl git
        # For eza and zoxide on RHEL/CentOS, recommend manual installation
        echo "Please install eza and zoxide manually for your RHEL/CentOS system"
    elif command_exists brew; then
        brew $package_to_install

        echo "Installing iTerm2..."
        brew install --cask iterm2

        echo "1. Launch iTerm2"
        echo "2. Set MesloLGS NF as the default font in iTerm2 preferences"
        echo "3. Import your iTerm2 preferences (if you have them in your dotfiles)"
    else
        echo "No supported package manager found. Please install zsh, curl, git, eza, and zoxide manually."
        exit 1
    fi
}

setup_powerlevel10k() {
    # First check if Oh My Zsh is installed
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "Oh My Zsh detected, setting up Powerlevel10k as Oh My Zsh theme..."
        
        # Install Powerlevel10k theme for Oh My Zsh if not already installed
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
            echo "Installing Powerlevel10k theme..."
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        else
            echo "Powerlevel10k theme is already installed for Oh My Zsh"
        fi
        
        # Check if ZSH_THEME is already set to powerlevel10k
        if grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$HOME/.zshrc"; then
            echo "Powerlevel10k theme is already configured in .zshrc"
        else
            # Backup existing .zshrc if it exists
            if [ -f "$HOME/.zshrc" ]; then
                echo "Backing up existing .zshrc..."
                cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
            fi
            
            # Update .zshrc configuration
            echo "Updating .zshrc to use Powerlevel10k theme..."
            sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        fi
    else
        echo "Oh My Zsh not detected, setting up standalone Powerlevel10k..."
        
        # Install standalone Powerlevel10k if not already installed
        if [ ! -d "$HOME/powerlevel10k" ]; then
            echo "Installing standalone Powerlevel10k..."
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"
        else
            echo "Standalone Powerlevel10k is already installed"
        fi
        
        # Check if powerlevel10k is already sourced in .zshrc
        if grep -q 'source ~/powerlevel10k/powerlevel10k.zsh-theme' "$HOME/.zshrc"; then
            echo "Standalone Powerlevel10k is already configured in .zshrc"
        else
            # Backup existing .zshrc if it exists
            if [ -f "$HOME/.zshrc" ]; then
                echo "Backing up existing .zshrc..."
                cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
            fi
            
            # Add source line to .zshrc
            echo "Adding Powerlevel10k source line to .zshrc..."
            echo "source ~/powerlevel10k/powerlevel10k.zsh-theme" >> "$HOME/.zshrc"
        fi
    fi
}

# Ensure script is run from the correct directory
if [ ! -d "$HOME/.dotfiles" ]; then
    echo "Error: ~/.dotfiles directory not found!"
    echo "Please clone the repository to ~/.dotfiles first."
    exit 1
fi

echo "Installing required packages..."
install_packages

# Check if Oh My Zsh is already installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "Oh My Zsh is already installed"
fi

# Backup existing .zshrc if it exists
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc..."
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

echo "Installing powerlevel10k..."
setup_powerlevel10k

# Install zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
else
    echo "zsh-autosuggestions is already installed"
fi

# Install zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
else
    echo "zsh-syntax-highlighting is already installed"
fi

# Create symlinks for dotfiles
create_symlinks

# Start services after symlinks are created
manage_services

# Update plugins in .zshrc
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"

# Add eza alias and zoxide configuration
echo "Adding eza alias and zoxide configuration..."
cat << 'EOF' >> "$HOME/.zshrc"

# ---- Eza (better ls) ----
alias ls="eza --icons=always"

# ---- Zoxide (better cd) ----
eval "$(zoxide init zsh)"
EOF

echo "================================================="
echo "Install & configure terminal"
echo "=================================================" 
brew install --cask alacritty
# install font
brew tap epk/epk
brew install --cask font-sf-mono-nerd-font

# Install recommended font (MesloLGS NF)
echo "Installing recommended Meslo Nerd Font..."
mkdir -p "$HOME/.local/share/fonts"
FONT_URLS=(
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
)


for URL in "${FONT_URLS[@]}"; do
    curl -fL "$URL" -o "$HOME/.local/share/fonts/$(basename "$URL")"
done

# Refresh font cache
if command_exists fc-cache; then
    fc-cache -f -v
fi

mkdir -p $HOME/.config/borders
ln -s .dotfiles/borders/bordersrc.symlink $HOME/.config/borders/bordersrc

echo "Installation complete!"
echo "Please:"
echo "1. Use iTerm2 as your default terminal"
echo "2. Change iTerm2 font to MesloLGS NF"
echo "3. Run 'p10k configure' to set up Powerlevel10k"
