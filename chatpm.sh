#!/bin/sh

# slogan: leave things as you found them, only liberated.

# Save the original working directory
original_dir=$(pwd)

# Define a function to be executed on exit
on_exit() {

    set +x
    echo "Script is exiting, builds remnants in .chatpm.build"
    echo "Would you like to remove the builds? (y/n)"
    read answer
    if [ "$answer" = "y" ]; then
        set -x
        rm -rf .chatpm.build
    fi
    set -x
    cd "$original_dir"
    exit $exit_code
}

# Set the function to be executed on exit
trap on_exit EXIT INT TERM

# slogan: depend on nothing.

OS=$(uname -s)
ARCH=$(uname -m)
DISTRIBUTION=""

case "$OS" in
    "Linux")
        if [ -f /etc/os-release ]; then
            DISTRIBUTION=$(awk -F= '/^PRETTY_NAME/{print $2}' /etc/os-release)
        elif command -v lsb_release > /dev/null; then
            DISTRIBUTION=$(lsb_release -d | cut -f2)
        fi
        ;;
    "Darwin") # macOS
        DISTRIBUTION=$(sw_vers -productVersion)
        ;;
    "MINGW"*|"MSYS_NT"*|"CYGWIN_NT"*) # Windows
        DISTRIBUTION=$(systeminfo | awk -F: '/^OS Version/{print $2}')
        ;;
esac

mkdir -p .chatpm.build
cd .chatpm.build

set -e
set -x



check_and_install_autoconf() {
    if ! command -v autoconf > /dev/null; then
        echo "autoconf not found, installing from source..."
        latest_version=$(curl -s ftp://ftp.gnu.org/gnu/autoconf/ | grep tar.gz | awk -F 'autoconf-' '{print $2}' | awk -F '.tar.gz' '{print $1}' | sort -V | tail -n 1)
        curl -L -O http://ftp.gnu.org/gnu/autoconf/autoconf-$latest_version.tar.gz
        tar xzf autoconf-$latest_version.tar.gz
        cd autoconf-$latest_version
        ./configure --prefix=/usr/local
        make
        sudo make install
        cd ..
    fi
}

check_and_install_autoconf

check_and_install_automake() {
    if ! command -v automake > /dev/null; then
        echo "automake not found, installing from source..."
        latest_version=$(curl -s ftp://ftp.gnu.org/gnu/automake/ | grep tar.gz | awk -F 'automake-' '{print $2}' | awk -F '.tar.gz' '{print $1}' | sort -V | tail -n 1)
        curl -L -O http://ftp.gnu.org/gnu/automake/automake-$latest_version.tar.gz
        tar xzf automake-$latest_version.tar.gz
        cd automake-$latest_version
        ./configure --prefix=/usr/local
        make
        sudo make install
        cd ..
    fi
}

check_and_install_automake

check_and_install_libtool() {
    if ! command -v libtool > /dev/null; then
        echo "libtool not found, installing from source..."
        latest_version=$(curl -s ftp://ftp.gnu.org/gnu/libtool/ | grep tar.gz | awk -F 'libtool-' '{print $2}' | awk -F '.tar.gz' '{print $1}' | sort -V | tail -n 1)
        curl -L -O http://ftp.gnu.org/gnu/libtool/libtool-$latest_version.tar.gz
        tar xzf libtool-$latest_version.tar.gz
        cd libtool-$latest_version
        ./configure --prefix=/usr/local
        make
        sudo make install
        cd ..
    fi
}

check_and_install_libtool

check_and_install_oniguruma() {
    echo '#include <oniguruma.h>' | gcc -E - > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "oniguruma not found, installing from source..."
        latest_version=$(curl --silent "https://api.github.com/repos/kkos/oniguruma/releases/latest" | grep '"tag_name":' | cut -d '"' -f 4 | cut -c 2-)
        curl -L -O "https://github.com/kkos/oniguruma/archive/refs/tags/v${latest_version}.tar.gz"
        tar xzf "v${latest_version}.tar.gz"
        cd "oniguruma-${latest_version}"
        autoreconf -vfi
        ./configure --prefix=/usr/local
        make
        sudo make install
        cd ..
    fi
}

check_and_install_oniguruma

check_and_install_jq() {
    if ! command -v jq > /dev/null; then
        echo "jq not found, installing from source..."
        latest_release=$(curl --silent -L "https://api.github.com/repos/jqlang/jq/releases/latest" | grep tarball_url | cut -d '"' -f 4)
        curl -L $latest_release -o jq-latest.tar.gz
        mkdir jq-src && tar -xzf jq-latest.tar.gz -C jq-src --strip-components 1
        cd jq-src

        autoreconf -fi
        ./configure --prefix=/usr/local
        make -j8
        make check
        sudo make install

        cd ..
    fi
}

check_and_install_jq

# set +x

cold_open="From now on, I'll be sending user prompts that are primarily requests to generate shell scripts. 
From now on, please format all responses as JSON objects with the following keys: 'response', 'details', 'timestamp', and 'script' for the shell script you generate in the response. 
Please respect the following preferences from now on: 
* Avoid package managers. 
* Write shell script as named functions followed by execution examples. 
* Write shell scripts for /bin/sh rather than /bin/bash whenever possible.
* Compile from source for all known operating systems.
* Use \"./configure --prefix=/usr/local\" and related features in other tools to install to /usr/local.
* Make sure shell scripts you write work with: 
    * OS: $OS 
    * Architecture: $ARCH 
    * Distribution: $DISTRIBUTION"


# Convert newlines to \n
cold_open_jq=$(jq -n --arg str "$cold_open" '$str | @json')

# Initialize the conversation with a system message
messages=$(jq -n --arg content "$cold_open_jq" '[{"role": "system", "content": $content | fromjson}]')

# Check if the OPENAI_API_KEY environment variable is set
# This is required to make requests to the OpenAI API
if [ -z "$OPENAI_API_KEY" ]
then
    echo "The OPENAI_API_KEY environment variable is not set."
    echo "Please set it to your OpenAI API key."
    echo "You need this to make requests to the OpenAI API."
    exit 1
fi

# Function to make a request to the OpenAI API
openai_request() {
    # Get the user's message, model, and URL from the function arguments
    local user_message_content="$1"
    local model=${2:-gpt-4}
    local url=${3:-"https://api.openai.com/v1/chat/completions"}
    # Define the user agent for the API request
    USER_AGENT="chatpm/1.0"

    # Append the user's message to the conversation
    user_message=$(jq -n --arg content "$user_message_content" '{"role": "user", "content": $content | @json}')
    new_messages=$(jq -n --arg msg "$user_message" '[($msg | fromjson)]')
    messages=$(echo "$messages" | jq --argjson new "$new_messages" '. += $new')

    # Make the API request and store the response
    RESPONSE=$(curl -L -s -X POST $url \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "User-Agent: $USER_AGENT" \
        --data "$(jq -n --arg model "$model" --arg messages "$messages" '{"model": $model, "messages": $messages}')")

    # Extract the assistant's message from the response
    assistant_message=$(echo "$RESPONSE" | jq -c '.choices[0].message | @json')
    new_messages=$(jq -n --arg msg "$assistant_message" '[($msg | fromjson)]')
    messages=$(echo "$messages" | jq --argjson new "$new_messages" '. += $new')

    # Print the response
    echo "$RESPONSE"
}
RESPONSE=$(openai_request "Write a shell script that installs the latest version of git.")
echo "$RESPONSE"
list_models() {
    local url="https://api.openai.com/v1/engines"

    USER_AGENT="chatpm/1.0"

    RESPONSE=$(curl -L -s -X GET $url \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "User-Agent: $USER_AGENT")

    echo "$RESPONSE"
}
# RESPONSE=$(list_models)
# echo "$RESPONSE"
