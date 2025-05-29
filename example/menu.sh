#!/bin/bash

# Create a whiptail menu and store the selected option
CHOICE=$(whiptail --title "Select an Option" --menu "Choose a number:" 10 40 4 \
"1" "Option 1" \
"2" "Option 2" \
"3" "Option 3" \
"4" "Option 4" 3>&1 1>&2 2>&3)

# Check if the user pressed Cancel or selected an option
if [ $? -eq 0 ]; then
    echo "You selected: $CHOICE"
else
    echo "Menu cancelled."
fi