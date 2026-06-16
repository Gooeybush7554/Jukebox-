#!/data/data/com.termux/files/usr/bin/bash

# --- Configuration ---
JUKEBOX_LIST="$HOME/.jukebox_list"
MUSIC_DIR="$HOME/Music"
SOCKET_DIR="$HOME/.termux_jukebox"
SOCKET="$SOCKET_DIR/mpvsocket"

mkdir -p "$SOCKET_DIR"
mkdir -p "$MUSIC_DIR"
touch "$JUKEBOX_LIST"

# --- Quick Git Update Checker ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "\e[1;34m[!] Checking for Jukebox updates...\e[0m"
    git fetch origin >/dev/null 2>&1
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse"@{u}")
    if [ "$LOCAL" != "$REMOTE" ]; then
        echo -e "\e[1;33m[!] A new Jukebox update is available! Run 'git pull'.\e[0m"
        sleep 2
    fi
fi

# --- Central Live Stream Audio Engine --- 
play_live_stream() { 
    local station_name="$1" 
    local stream_url="$2" 
    
    echo -e "\e[1;32m[!] Connecting to  ${station_name}...\e[0m" 
    
    # 1. Kill background mpv instances by exact binary name (prevents killing your script)
    pkill mpv 2>/dev/null
    rm -f "$SOCKET" 
    
    # 2. Launch background MPV with buffering protection (No nohup.out clutter) 
    { 
        mpv --no-video \
            --input-ipc-server="$SOCKET" \
            --cache=yes \
            --cache-secs=10 \
            "$stream_url" > /dev/null 2>&1 
    } & 
    
    # 3. Synchronize socket creation before handing UI back to the menu 
    for i in {1..5}; do 
        [ -S "$SOCKET" ] && break 
        sleep 0.5 
    done 
}

# --- Center Text Function ---
center_text() {
    local text="$1"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    
    # This line strips out the ANSI color codes to find the TRUE visible length
    local visible_len
    visible_len=$(echo -e "$text" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | wc -m)
    # Adjust for newline character count
    ((visible_len--))

    # Calculate padding based on true visual letters
    local padding=$(( (term_width - visible_len) / 2 ))
    
    if [ $padding -gt 0 ]; then
        printf "%${padding}s" ""
    fi
    echo -e "$text"
}

draw_rainbow_banner() {
    clear
    local msg="---💎 JUKEBOX - Diamond Edition 💎---"
    local colors=(31 33 32 36 34 35)
    local colored_text=""
    for (( i=0; i<${#msg}; i++ )); do
        colored_text+="\e[1;${colors[i % 6]}m${msg:i:1}"
    done
    center_text "${colored_text}\e[0m"
}

get_status() {
    local status_str=""
    
    # 1. Check for active music playback status
    if pgrep -x "mpv" > /dev/null; then
        if [ -S "$SOCKET" ]; then
            is_paused=$(echo '{ "command": ["get_property", "pause"] }' | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null | grep -o "true")
            if [ "$is_paused" == "true" ]; then
                status_str="\e[1;33m[ ⏸  PAUSED ]\e[0m"
            else
                status_str="\e[1;32m[ 🎶 PLAYING 🎵]\e[0m"
            fi
        else
            status_str="\e[1;36m[🛑 INITIALIZING..]\e[0m"
        fi
    else
        status_str="\e[1;31m[⏹  STOPPED ]\e[0m"
    fi

    # 2. Add the blinking recording reminder light if the background rip engine is active
    if [ -f "$SOCKET_DIR/ripper.pid" ]; then
        status_str="$status_str \e[1;5;31m[ 🔴 RECORDING ]\e[0m"
    fi

    echo -e "$status_str"
}

control_mpv() {
    if ! pgrep -x "mpv" > /dev/null; then
        echo -e "\e[1;31mError: mpv is not running. Select a track first!\e[0m"
        sleep 1
        return
    fi
    if [ -S "$SOCKET" ]; then
        echo '{ "command": ["cycle", "pause"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
    else
        echo "Error: IPC Socket not found at $SOCKET"
        sleep 2
    fi
}

send_mpv() {
    local cmd="$1"
    local arg1="$2"
    local arg2="$3"
    if [ -S "$SOCKET" ]; then
        # Properly structures the JSON IPC string for complex multi-argument mpv commands
        printf '{ "command": ["%s", "%s", "%s"] }\n' "$cmd" "$arg1" "$arg2" | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
    fi
}

update_library() {
    echo -e "\e[1;33m[!] Scanning & Cleaning Library...\e[0m"
    
    # 1. Cleanup: Remove entries where the file no longer exists
    TEMP_CLEAN=$(mktemp)
    while IFS= read -r line; do
        path=$(echo "$line" | cut -d'|' -f2)
        if [[ "$path" == /* ]]; then
            if [ -f "$path" ]; then
                echo "$line" >> "$TEMP_CLEAN"
            fi
        else
            # Keep URLs (radio stations)
            echo "$line" >> "$TEMP_CLEAN"
        fi
    done < "$JUKEBOX_LIST"
    mv "$TEMP_CLEAN" "$JUKEBOX_LIST"

    # 2. Scan: Add new files found in Music directory
    find "$MUSIC_DIR" -maxdepth 2 -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" \) -print0 | while IFS= read -r -d $'\0' file; do
        filename=$(basename "$file")
        name="${filename%.*}"
        if ! grep -qF "|$file" "$JUKEBOX_LIST"; then
            echo "$name|$file" >> "$JUKEBOX_LIST"
            echo -e "\e[1;32m[+] Added: $name\e[0m"
        fi
    done
    sleep 1
}

# --- Dependency Installer ---
dependencies=(mpv socat yt-dlp streamripper sox python)
missing_deps=()

for dep in "${dependencies[@]}"; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    missing_deps+=("$dep")
  fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
  clear
  echo "========================================="
  echo "      ⚙️ INSTALLING DEPENDENCIES ⚙️     "
  echo "========================================="
  echo "Missing: ${missing_deps[*]}"
  echo "Updating Termux repositories..."
  echo ""
  
  # Termux updates repositories automatically with pkg
  pkg update -y
  
  echo ""
  echo "Installing missing components..."
  
  # Straightforward Termux package installation
  pkg install "${missing_deps[@]}" -y
  
  clear
fi

# --- Initial Setup ---
if [ ! -s "$JUKEBOX_LIST" ]; then
    cat << EOF > "$JUKEBOX_LIST"
Waylon & Willie/Pancho and Lefty|https://youtu.be/UoKvUYbGu7A?si=Cg-kJfYw-dP1ev_B
George Jones/Who's gonna fill their shoes|https://youtu.be/vxHjRqnY7zA?si=ikkMn11ptu9AHAeN
Waylon & Willie/Mommas don't let your babies grow up to be cowboys|https://youtu.be/i85ob2DackI?si=wzrcmnZBFij_i7pj
Conway Twitty/I'd just love to lay you down|https://youtu.be/66EbiU04hGY?si=RDt690XPd9isu5O2
David Allen Coe/If that ain't country|https://youtu.be/b3UywbiT0XA?si=1cVY5EYlEFzB49tl
EOF
fi

# Initial scan
update_library

# --- Main Loop ---
while true; do
    draw_rainbow_banner
    IFS=$'\n' read -d '' -r -a stations < <(cat "$JUKEBOX_LIST" 2>/dev/null)
    
    center_text "\e[1;36m════════════════════════════════════════\e[0m"
    status_line=$(get_status)
    center_text "\e[1;37mSTATUS: $status_line\e[0m"
    center_text "\e[1;37mCHANNELS & LIBRARY\e[0m"
    
    num_stations=${#stations[@]}
    for ((i=0; i<num_stations; i+=2)); do
        name1=$(echo "${stations[$i]}" | cut -d'|' -f1)
        [ ${#name1} -gt 15 ] && name1="${name1:0:12}..."
        col1=$(printf "\e[1;35m%2d)\e[0m %-16s" "$((i+1))" "$name1")
        if [ $((i+1)) -lt "$num_stations" ]; then
            name2=$(echo "${stations[$((i+1))]}" | cut -d'|' -f1)
            [ ${#name2} -gt 15 ] && name2="${name2:0:12}..."
            col2=$(printf "\e[1;35m%2d)\e[0m %-16s" "$((i+2))" "$name2")
        else
            col2=""
        fi
        center_text "${col1}    ${col2}"
    done
    
    center_text "\e[1;36m════════════════════════════════════════\e[0m"
    center_text "\e[1;35m🎵🎶 JUKEBOX 🎼\e[0m        \e[1;31m[s]\e[0m Stop"
    center_text "\e[1;32m[m]\e[0m Mute/Unmute     \e[1;35m[0]\e[0m Quit"
    center_text "\e[1;33m[u/d]\e[0m Move    \e[1;34m[p]\e[0m Pause/Play    \e[1;32m[+/-]\e[0m Vol"
    center_text "\e[1;34m[a]\e[0m Add     \e[1;35m[r]\e[0m Remove     \e[1;32m[dl]\e[0m Download"
    center_text "\e[1;35m[q]\e[0m Queue track   \e[1;34m[sr]\e[0m Search   \e[1;33m[cq]\e[0m Clear Queue" 
    center_text "\e[1;32m[sh]\e[0m Shuffle     \e[1;35m[l]\e[0m Load List.     \e[1;34m[n]\e[0m Next Song"
    center_text "\e[1;33m[cp]\e[0m Cont-Play    \e[1;31m[rs]\e[0m Reset MPV"
    center_text "\e[1;36m════════════════════════════════════════\e[0m"
    center_text "\e[1;36m[eq]\e[0m EQ FX   \e[1;32m[rec]\e[0m Record Stream"
    center_text "\e[1;95m[s1]\e[0m Live Stream KTDY      \e[1;95m[s2]\e[0m Live Stream 80s Era"
    center_text "\e[1;95m[s3]\e[0m Live Stream 70s Rock      \e[1;95m[s4]\e[0m Live Bob FM"
    echo -ne "\n\e[1;32m   Selection > \e[0m"
    read -r cmd
    case ${cmd,,} in
        cq) echo '{ "command": ["playlist-clear"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1 ;;
        eq) # Dynamic Audio EQ & FX Helper

            # Check if mpv is currently running
            if pgrep -x "mpv" > /dev/null; then
                STATUS="\e[1;32m[● ONLINE]\e[0m"
            else
                STATUS="\e[1;31m[○ OFFLINE]\e[0m"
            fi

            # Present sub-menu choices with the live status indicator
            echo -e "\e[1;35m\n--- Jukebox Equalizer Effects --- $STATUS\e[0m"
            echo -e "  \e[1;32m1)\e[0m 📢 Loudness Enhancer (Clear / Crisp)"
            echo -e "  \e[1;32m2)\e[0m 🔊 Club Bass Booster (Heavy Low-End)"
            echo -e "  \e[1;32m3)\e[0m 🗣️  Vocal & Speech Booster (Clear Dialogue)"
            echo -e "  \e[1;32m4)\e[0m 🌌 Mono Downmix & Equal Balance"
            echo -e "  \e[1;32m5)\e[0m ⏹  Flat EQ (Reset / Bypass)"
            echo ""
            
            read -r -p " Select FX Profile # : " fx_choice

            # Gatekeeper: Prevents applying filters if mpv is offline
            if [ "$STATUS" = "\e[1;31m[○ OFFLINE]\e[0m" ] && [ "$fx_choice" != "5" ]; then
                echo -e "\e[1;31m[!] Cannot apply FX. Start playing audio in mpv first!\e[0m"
                sleep 2
                continue
            fi

            case "$fx_choice" in
                1) # Custom Loudness Enhancer for clearer speech and boosted volume
                   echo -e "\e[1;32m[+] Activating Loudness Enhancer Profile...\e[0m"
                   echo '{ "command": ["set_property", "af", "loudnorm=I=-12:TP=-1.0:LRA=7"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
                   sleep 1
                   ;;
                2) # Uses a parametric equalizer to heavily boost frequencies under 100Hz
                   echo -e "\e[1;33m[+] Activating Club Bass Booster Profile...\e[0m"
                   echo '{ "command": ["set_property", "af", "loudnorm=I=-14:LRA=7,equalizer=f=60:width_type=h:width=40:g=8,equalizer=f=100:width_type=h:width=60:g=4"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
                   sleep 1
                   ;;
                3) # Vocal & Speech Booster (Optimized for Hearing Loss Clarity)
                   echo -e "\e[1;32m[+] Activating Vocal & Speech Booster Profile...\e[0m"
                   # This line squishes dynamic range AND pumps up mid-to-high speech frequencies
                   echo '{ "command": ["set_property", "af", "loudnorm=I=-14:LRA=7,equalizer=f=1000:width_type=o:w=1:g=3,equalizer=f=3000:width_type=o:w=1:g=6"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
                   sleep 1
                   ;;
                4) # Mono Downmix & Equal Balance (No Missed Audio)
                   echo -e "\e[1;32m[+] Activating Mono Balanced Profile...\e[0m"
                   # Blends left and right channels perfectly into both ears
                   echo '{ "command": ["set_property", "af", "pan=mono:c0=0.5*c0+0.5*c1:c1=0.5*c0+0.5*c1"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
                   sleep 1
                   ;;
                5) # Flat EQ (Reset / Bypass)
                   echo -e "\e[1;32m[+] Resetting Audio Filters to Default...\e[0m"
                   echo '{ "command": ["set_property", "af", ""] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1
                   sleep 1
                   ;;
                *)
                   echo -e "\e[1;31m[!] Invalid EQ Profile choice.\e[0m" && sleep 1
                   ;;
            esac
            ;;
        sh) # Continuous Shuffle Play
            echo -e "\e[1;33m[!] Shuffling everything for a long session...\e[0m"
            pkill mpv
            rm -f "$SOCKET"
            # Create a temporary playlist file for mpv
            TMP_PL=$(mktemp)
            cut -d'|' -f2 "$JUKEBOX_LIST" | shuf > "$TMP_PL"
            nohup mpv --no-video --gapless-audio=yes --playlist="$TMP_PL" --input-ipc-server="$SOCKET" > /dev/null 2>&1 &
            sleep 1; rm "$TMP_PL"
            ;;
         q)
            read -r -p "Track # to Queue: " q_idx
            if [[ "$q_idx" =~ ^[0-9]+$ ]] && [ "$q_idx" -ge 1 ] && [ "$q_idx" -le "$num_stations" ]; then
                url=$(echo "${stations[$((q_idx-1))]}" | cut -d'|' -f2)
                
                if pgrep -x "mpv" >/dev/null && [ -S "$SOCKET" ]; then 
                    send_mpv "loadfile" "$url" "append"
                    echo -e "\e[1;32m[+] Track added to queue!\e[0m" && sleep 1
                else 
                    # If mpv isn't up, spawn it cleanly and pass the first track
                    track_name=$(echo "${stations[$((q_idx-1))]}" | cut -d'|' -f1)
                    play_live_stream "$track_name" "$url"
                fi
            else
                echo "Invalid selection."; sleep 1
            fi
            ;;
        dl)
            echo -ne "\e[1;32m   Paste Music URL > \e[0m"
            read -r dl_url
            if [ -n "$dl_url" ]; then
                echo -e "\e[1;33m[!] Downloading high-quality audio...\e[0m"
                yt-dlp -x --audio-format mp3 --audio-quality 0 \
                       -o "$MUSIC_DIR/%(title)s.%(ext)s" "$dl_url"
                echo -e "\e[1;32m[+] Download complete!\e[0m"
                update_library
                sleep 2
            fi
            ;;
        rec) # Background Streamripper Hook (Termux-Safe Paths)
            if ! pgrep -x "mpv" > /dev/null; then
                echo -e "\e[1;31m[!] You must be playing a live stream to record!\e[0m" && sleep 1
                continue
            fi

            REC_DIR="$MUSIC_DIR/Recordings"
            mkdir -p "$REC_DIR"
            
            # FIXED: Uses your safe Jukebox directory instead of Android's locked global /tmp
            PID_FILE="$SOCKET_DIR/ripper.pid"

            if [ -f "$PID_FILE" ]; then
                # --- STOP RECORDING ---
                rip_pid=$(cat "$PID_FILE")
                echo -e "\e[1;31m[!] Stopping background recording (PID: $rip_pid)...\e[0m"
                kill "$rip_pid" 2>/dev/null
                rm -f "$PID_FILE"
                sleep 1
                update_library
            else
                # --- START RECORDING ---
                active_url=$(echo '{ "command": ["get_property", "path"] }' | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null | grep -o '"data":"[^"]*' | cut -d'"' -f4)

                if [ -z "$active_url" ] || [[ "$active_url" == "null" ]]; then
                    echo -e "\e[1;31m[!] Could not parse active stream URL from socket!\e[0m" && sleep 2
                    continue
                fi

                echo -e "\e[1;32m[🔴] Spawning Background Stream Capture Engine...\e[0m"
                echo -e "\e[1;37mSaving tracks to: $REC_DIR\e[0m"

                TIMESTAMP=$(date +"%Y%m%d_%H%M")
                nohup streamripper "$active_url" -d "$REC_DIR" -a -A -o "KTDY_Rip_$TIMESTAMP" > /dev/null 2>&1 &
                # Save the tracking PID to our safe socket directory
                echo $! > "$PID_FILE"
                sleep 1.5
            fi
            ;;
        l)
            echo -e "\e[1;33m[!] Drop a folder path or .txt playlist file here:\e[0m"
            read -r -p "   Path > " pl_path
            
            # Remove leading/trailing quotes if user dragged and dropped the file
            pl_path="${pl_path%\"}"
            pl_path="${pl_path#\"}"
            pl_path="${pl_path%\'}"
            pl_path="${pl_path#\'}"

            if [ -d "$pl_path" ]; then
                # Load all music in a folder safely using process substitution
                while IFS= read -r -d '' f; do
                    send_mpv "loadfile" "$f" "append"
                done < <(find "$pl_path" -type f \( -iname "*.mp3" -o -iname "*.flac" \) -print0)
                echo "Folder added to queue!" && sleep 1
                
            elif [ -f "$pl_path" ]; then
                # Load tracks from a text file safely
                while IFS= read -r line; do
                    # Skip comments and empty lines
                    [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]] && continue
                    send_mpv "loadfile" "$line" "append"
                done < "$pl_path"
                echo "Playlist file loaded!" && sleep 1
            else
                echo -e "\e[1;31m[!] Invalid path or file!\e[0m" && sleep 1
            fi
            ;;
        p) control_mpv ;;
        s) pkill mpv && rm -f "$SOCKET" ;;
        0) exit 0 ;;    
        m) echo '{ "command": ["cycle", "mute"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1 ;;
        n) echo '{ "command": ["playlist-next"] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1 ;;
        a) 
            read -r -p "Name: " new_name
            read -r -p "URL/Path: " new_url
            echo "$new_name|$new_url" >> "$JUKEBOX_LIST"
            ;;
        r)
            read -r -p "Remove # : " idx
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "$num_stations" ]; then
                sed -i "${idx}d" "$JUKEBOX_LIST"
            fi
            ;;  
        u)
            read -r -p "Move UP # : " idx
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -gt 1 ] && [ "$idx" -le "$num_stations" ]; then
                python3 -c "import sys; lines = open('$JUKEBOX_LIST').readlines(); i = int('$idx') - 1; lines[i], lines[i-1] = lines[i-1], lines[i]; open('$JUKEBOX_LIST', 'w').writelines(lines)"
            fi
            ;;  
        d)
            read -r -p "Move DOWN # : " idx
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -lt "$num_stations" ]; then
                python3 -c "import sys; lines = open('$JUKEBOX_LIST').readlines(); i = int('$idx') - 1; lines[i], lines[i+1] = lines[i+1], lines[i]; open('$JUKEBOX_LIST', 'w').writelines(lines)"
            fi
            ;;  
        +) echo '{ "command": ["add", "volume", 15] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1 ;;
        -) echo '{ "command": ["add", "volume", -15] }' | socat - "UNIX-CONNECT:$SOCKET" >/dev/null 2>&1 ;;
        [1-9]*)
            if [[ "$cmd" =~ ^[0-9]+$ ]] && [ "$cmd" -le "${#stations[@]}" ]; then
                track_name=$(echo "${stations[$((cmd-1))]}" | cut -d'|' -f1)
                url=$(echo "${stations[$((cmd-1))]}" | cut -d'|' -f2)
                
                # Diverts both local files and internet streams through your safe loader
                play_live_stream "$track_name" "$url"
            else
                echo "Invalid selection."; sleep 1
            fi
            ;;
        sr) # Search ONLY the jukebox library file
            echo -e "\e[1;33m[!] Scanning Jukebox Library...\e[0m"
            
            # 1. We ONLY feed fzf the specific text lines from your playlist index
            # 2. --delimiter and --with-nth ensure you only view the Song Title, hiding raw paths
            CHOICE=$(cut -d'|' -f1,2 "$JUKEBOX_LIST" | fzf --delimiter='|' --with-nth=1 --tty=ok)
            
            if [ -n "$CHOICE" ]; then
                # Extract track title and hidden path destination safely
                track_name
                track_name=$(echo "$CHOICE" | cut -d'|' -f1)
                TRACK_PATH=$(echo "$CHOICE" | cut -d'|' -f2)
                
                if pgrep -x "mpv" >/dev/null && [ -S "$SOCKET" ]; then
                    send_mpv "loadfile" "$TRACK_PATH" "replace"
                    echo "Playing choice!" && sleep 1
                else
                    # Secure fallback: If mpv is dead, fire up the central audio engine
                    play_live_stream "$track_name" "$TRACK_PATH"
                fi
            else
                echo "Search canceled." && sleep 1
            fi
            ;;
         s1) # Live Stream KTDY
            play_live_stream "KTDY" "https://live.amperwave.net/direct/townsquare-ktdyfmaac-ibc3"
            ;;
        s2) # Live Stream 80s Hairbands
            play_live_stream "80s Hairbands" "https://listen.181fm.com/181-hairband_128k.mp3"
            ;; 
        s3) # Live Stream 70s Rock
            play_live_stream "70s Rock" "https://listen.181fm.com/181-70s_128k.mp3"
            ;; 
        s4) # Live Bob FM
            play_live_stream "Big FM" "https://ais-sa1.streamon.fm/7164_48k.aac"
            ;;
        cp) 
            echo -e "\e[1;33m[!] Starting Continuous Playback...\e[0m"
            pkill mpv; rm -f "$SOCKET"
            TMP_PL=$(mktemp)
            cut -d'|' -f2 "$JUKEBOX_LIST" > "$TMP_PL"
            nohup mpv --no-video --playlist="$TMP_PL" --playlist-start=0 --no-resume-playback --input-ipc-server="$SOCKET" > /dev/null 2>&1 &
            sleep 1; rm "$TMP_PL"
            ;;
        rs) # Restart / Reset MPV Engine
            echo -e "\e[1;31m[!] Resetting MPV audio engine...\e[0m"
            
            # 1. Kill any existing or frozen mpv instances
            pkill -9 mpv >/dev/null 2>&1
            
            # 2. Force clean the broken socket file
            rm -f "$SOCKET"
            sleep 0.5
            
            # 3. Launch a fresh, clean idle instance of mpv
            nohup mpv --idle \
                      --no-video \
                      --input-ipc-server="$SOCKET" > /dev/null 2>&1 &
                      
            # 4. Wait a brief moment for the socket to initialize
            sleep 1
            
            if [ -S "$SOCKET" ]; then
                echo -e "\e[1;32m[+] Audio engine successfully restarted!\e[0m" && sleep 1
            else
                echo -e "\e[1;31m[-] Restart failed. Check your socket path.\e[0m" && sleep 1
            fi
            ;;
        *) 
            echo -e "\e[1;31m[!] Invalid selection!\e[0m" && sleep 1
            ;;
    esac
done
