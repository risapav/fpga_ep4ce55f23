# ========================================================================== #
#                    PIN ASSIGNMENT LIBRARY (Tcl Script)                     #
# ========================================================================== #
#
# This script assigns physical pins based on the module type specified in the
# main .qsf file for connectors J10 and J11.
# Do not call this script directly. It is sourced by the main .qsf file.
#
# Author: Your Name
# Date:   2025-09-12
#
# ========================================================================== #

# Procedure to assign pins for a given connector and module type
# This makes the code reusable and clean.
proc assign_module { port_name module_type } {

    # -------------------------------------------------------------------------- #
    #                     *** VALIDATION BLOCK ***
    # -------------------------------------------------------------------------- #
    # This section checks for known hardware limitations before attempting
    # to assign any pins.

    # KONTROLA 1: HDMI modul vyžaduje LVDS piny, ktoré sú len na J11.
    if { [string compare -nocase $module_type "HDMI"] == 0 && \
          [string compare -nocase $port_name "J10"] == 0 } {

        # Vypíš zrozumiteľnú chybu a zastav kompiláciu
        post_message -type error "INVALID CONFIGURATION: Attempted to assign HDMI module to connector J10."
        post_message -type error "REASON: The FPGA pins for J10 do not support the required LVDS I/O standard for HDMI."
        post_message -type error "SOLUTION: Please assign the HDMI module to a compatible connector (e.g., J11) in your project.qsf file."

        # Ukončí procedúru a vráti chybový stav, čo zastaví ďalšie spracovanie
        return -code error
    }

    # Tu môžete v budúcnosti pridať ďalšie kontroly pre iné moduly...

    # -------------------------------------------------------------------------- #
    #                  *** PIN DEFINITIONS AND ASSIGNMENTS ***
    # -------------------------------------------------------------------------- #

    # --- Define physical pins for each connector ---
    array set PINS_J10 {
        1 "PIN_H1"   7 "PIN_H2"
        2 "PIN_F1"   8 "PIN_F2"
        3 "PIN_E1"   9 "PIN_D2"
        4 "PIN_C1"  10 "PIN_C2"
    }
    array set PINS_J11 {
        1 "PIN_R1"   7 "PIN_R2"
        2 "PIN_P1"   8 "PIN_P2"
        3 "PIN_N1"   9 "PIN_N2"
        4 "PIN_M1"  10 "PIN_M2"
    }

    # Select the correct pin array based on the port name
    if {$port_name == "J10"} {
        array set PINS [array get PINS_J10]
    } elseif {$port_name == "J11"} {
        array set PINS [array get PINS_J11]
    } else {
        post_message -type error "Unknown port name: $port_name"
        return
    }

    # --- Use a switch statement to select the correct assignment logic ---
    switch -exact -- $module_type {

        "LED" {
            post_message "INFO: PMOD_LEDx8 Assigning 8-bit LED module to $port_name."
            set signal_name "LED_${port_name}"
            set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "${signal_name}[7..0]"
            set_location_assignment $PINS(1) -to "${signal_name}[0]"
            set_location_assignment $PINS(2) -to "${signal_name}[1]"
            set_location_assignment $PINS(3) -to "${signal_name}[2]"
            set_location_assignment $PINS(4) -to "${signal_name}[3]"
            set_location_assignment $PINS(7) -to "${signal_name}[4]"
            set_location_assignment $PINS(8) -to "${signal_name}[5]"
            set_location_assignment $PINS(9) -to "${signal_name}[6]"
            set_location_assignment $PINS(10) -to "${signal_name}[7]"
        }

        "HDMI" {
            post_message "INFO: PMOD_DVI: Assigning HDMI module to $port_name."
            set signal_p_name "HDMI_P_${port_name}"
            set_instance_assignment -name IO_STANDARD "LVDS" -to "${signal_p_name}[3..0]"

            # NOTE: Only positive pins of LVDS pairs are assigned.
            # The Quartus Fitter will automatically assign the corresponding negative pins.

            # Differential Pair for Red Channel
            set_location_assignment $PINS(7) -to "${signal_p_name}[2]"
            # Differential Pair for Green Channel
            set_location_assignment $PINS(8) -to "${signal_p_name}[1]"
            # Differential Pair for Blue Channel
            set_location_assignment $PINS(9) -to "${signal_p_name}[0]"
            # Differential Pair for Clock Channel
            set_location_assignment $PINS(10) -to "${signal_p_name}[3]"
        }

        "SEG7" {
            post_message "INFO: PMOD_DTx2 Assigning 8-bit 7 SEGMENT module to $port_name."
            set signal_name "SEG7_${port_name}"
            set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "${signal_name}[7..0]"
            set_location_assignment $PINS(1) -to "${signal_name}[0]"
            set_location_assignment $PINS(2) -to "${signal_name}[1]"
            set_location_assignment $PINS(3) -to "${signal_name}[2]"
            set_location_assignment $PINS(4) -to "${signal_name}[3]"
            set_location_assignment $PINS(7) -to "${signal_name}[4]"
            set_location_assignment $PINS(8) -to "${signal_name}[5]"
            set_location_assignment $PINS(9) -to "${signal_name}[6]"
            set_location_assignment $PINS(10) -to "${signal_name}[7]"
        }

        # --- ADD NEW MODULES HERE ---
        # "BUTTONS" {
        #    post_message "INFO: Assigning BUTTON module to $port_name."
        #    # ... your assignments for buttons ...
        # }

        "NONE" {
            post_message "INFO: $port_name is configured as unused."
        }

        default {
            post_message -type warning "WARNING: Unknown module type '$module_type' for $port_name. No pins assigned."
        }
    }
}

# ========================================================================== #
#                              *** MAIN LOGIC *** #
# ========================================================================== #
#
# Call the procedure for each connector.
# The variables $J10_MODULE and $J11_MODULE are defined in the main .qsf file.

if {[info exists J10_MODULE]} {
    assign_module "J10" $J10_MODULE
}
if {[info exists J11_MODULE]} {
    assign_module "J11" $J11_MODULE
}
