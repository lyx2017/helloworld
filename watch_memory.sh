#!/bin/bash

# Function to get PSS value
get_pss() {
  pid=$1
  awk '/^Pss:/ { sum += $2 } END { print sum }' /proc/$pid/smaps 2>/dev/null
}

# Function to get SWAP value
get_swap() {
  pid=$1
  awk '/^Swap:/ { sum += $2 } END { print sum }' /proc/$pid/smaps 2>/dev/null
}

# Function to print usage
print_usage() {
  echo "Usage: $0 [-a | -s] <software_name1> [<software_name2> ...]"
  echo 
  echo "Mode      | PSS (ps) | PSS (smaps) | SWAP (smaps)"
  echo "-----------------------------------------------"
  echo "Default   |    ✔     |             |      ✔"
  echo "Accurate  |          |      ✔      |      ✔"
  echo "Speed     |    ✔     |             |"
  echo
  script_name=$(basename "$0")
  echo "Example: ./$script_name kde plasma"
}

# Check if a software name parameter is provided
if [ -z "$1" ]; then
  print_usage
  exit 1
fi

# Parse options and software names
MODE="default"
INTERVAL=5
SOFTWARES=()

while true; do
  case "$1" in
    -a)
      if [ "$MODE" != "default" ]; then
        echo "Error: Multiple modes specified."
        print_usage
        exit 1
      fi
      MODE="accurate"
      INTERVAL=10
      shift
      ;;
    -s)
      if [ "$MODE" != "default" ]; then
        echo "Error: Multiple modes specified."
        print_usage
        exit 1
      fi
      MODE="speed"
      INTERVAL=1
      shift
      ;;
    *)
      if [ -z "$1" ]; then
        break
      fi
      SOFTWARES+=("$1")
      shift
      ;;
  esac
done

# If no software names are provided, print usage and exit
if [ ${#SOFTWARES[@]} -eq 0 ]; then
  print_usage
  exit 1
fi

# Export functions so they can be used in subshells
export -f get_pss
export -f get_swap

# Create a regex pattern for the software names
SOFTWARE_PATTERN=$(IFS="|"; echo "${SOFTWARES[*]}")

# Execute the monitoring command with dynamic CMD width
watch -n $INTERVAL "
  TERMINAL_WIDTH=\$(tput cols)
  if [ \"$MODE\" = \"speed\" ]; then
    echo 'No.     PID    PPID  NLWP  %CPU   PSS(MB) CMD'
  else
    echo 'No.     PID    PPID  NLWP  %CPU   PSS(MB)   SWAP(MB) CMD'
  fi
  ps -eo pid,ppid,nlwp,%cpu,pss,cmd --sort=-pss | grep -E -i \"$SOFTWARE_PATTERN\" | grep -v -E \"grep|$0\" | 
  awk -v terminal_width=\$TERMINAL_WIDTH -v mode=\"$MODE\" -v get_pss_cmd=\"get_pss\" -v get_swap_cmd=\"get_swap\" '
    function fetch_pss(pid) {
      cmd = get_pss_cmd \" \" pid
      cmd | getline result
      close(cmd)
      return (result == \"\" ? 0 : result / 1024)
    }

    function fetch_swap(pid) {
      cmd = get_swap_cmd \" \" pid
      cmd | getline result
      close(cmd)
      return (result == \"\" ? 0 : result / 1024)
    }

    BEGIN {
      total_pss=0
      total_swap=0
      total_cpu=0
      total_threads=0
    }
    {
      pid=\$1
      if (mode == \"accurate\") {
        pss = fetch_pss(pid)
        swap = fetch_swap(pid)
      } else {
        pss = \$5 / 1024
        swap = (mode == \"speed\" ? 0 : fetch_swap(pid))
      }
      total_pss+=pss
      total_swap+=swap
      # Find the position of the first non-digit, non-period, non-space character to start CMD
      cmd_start = match(\$0, /[^0-9\\. ]/)
      
      # Calculate the width for the other columns based on printf format, adjusted for correct spacing
      if (mode == \"speed\") {
        other_columns_width = 3 + 7 + 7 + 5 + 5 + 9 + 7  # Based on the format string: %3d %7s %7s %5s %5s %9.2f %s
      } else {
        other_columns_width = 3 + 7 + 7 + 5 + 5 + 9 + 10 + 7  # Based on the format string: %3d %7s %7s %5s %5s %9.2f %10.2f %s
      }
      
      # Calculate CMD width based on terminal width
      cmd_width = terminal_width - other_columns_width
      
      # Ensure CMD_WIDTH is positive
      cmd_width = (cmd_width > 0 ? cmd_width : 10)
      
      # Truncate CMD to dynamic width starting from the correct position
      cmd = substr(\$0, cmd_start, cmd_width)
      if (mode == \"speed\") {
        printf \"%3d %7s %7s %5s %5s %9.2f %s\\n\", NR, \$1, \$2, \$3, \$4, pss, cmd
      } else {
        printf \"%3d %7s %7s %5s %5s %9.2f %10.2f %s\\n\", NR, \$1, \$2, \$3, \$4, pss, swap, cmd
      }
      
      # Accumulate total CPU usage and total threads
      total_cpu += \$4
      total_threads += \$3
    }
    END {
      total_memory = total_pss + total_swap
      if (total_memory > 1024) {
        total_memory_str = sprintf(\"%.2f GB\", total_memory / 1024)
      } else {
        total_memory_str = sprintf(\"%.2f MB\", total_memory)
      }
      if (total_pss > 1024) {
        total_pss_str = sprintf(\"%.2f GB\", total_pss / 1024)
      } else {
        total_pss_str = sprintf(\"%.2f MB\", total_pss)
      }
      if (total_swap > 1024) {
        total_swap_str = sprintf(\"%.2f GB\", total_swap / 1024)
      } else {
        total_swap_str = sprintf(\"%.2f MB\", total_swap)
      }
      if (mode == \"speed\") {
        printf \"\\nTotal PSS Used: %s\\n\", total_pss_str
      } else {
        printf \"\\nTotal Memory Used: %s (PSS: %s, SWAP: %s)\\n\", total_memory_str, total_pss_str, total_swap_str
      }
      printf \"Total CPU Usage: %.2f%%  Total Threads: %d\\n\", total_cpu, total_threads
    }'
"