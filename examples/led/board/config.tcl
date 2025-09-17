# -------------------------------------------------------------------------- #
#      *** HARDWARE CONFIGURATION - ONBOARD PERIPHERALS - EDIT THIS SECTION *** #
# -------------------------------------------------------------------------- #
# Enable (1) or disable (0) the onboard peripherals for this project.
# Disabling a peripheral will prevent its logic from being synthesized and
# its pins from being assigned.

set USE_7_SEG_DISPLAY   0
set USE_LEDS            1
set USE_BUTTONS         0
set USE_VGA             0  ;# VGA v tomto projekte nepoužívame
set USE_SDRAM           0  ;# SDRAM v tomto projekte nepoužívame
set USE_UART            0

# -------------------------------------------------------------------------- #
#      *** HARDWARE CONFIGURATION - PMOD CONNECTORS - EDIT THIS SECTION *** #
# -------------------------------------------------------------------------- #
# Specify which module is connected to which PMOD connector.
# Supported modules: "LED", "HDMI", "BUTTONS", "7SEG", etc.
# Use "NONE" if the connector is not used.

set J10_MODULE "LED"
set J11_MODULE "LED"
