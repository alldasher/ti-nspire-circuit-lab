# H1 Circuit Lab for TI-Nspire CX CAS

**Ready-to-transfer calculator file:** [Download H1_CIRCUIT_LAB_MEASURE.tns](https://github.com/alldasher/ti-nspire-circuit-lab/raw/refs/heads/main/H1_CIRCUIT_LAB_MEASURE.tns)

Copy the `.tns` file to your calculator with TI-Nspire Link Software (N-Link), then open it as a document. This version includes direct DC and AC measurements and a circuit editor designed for the calculator screen.

## Drawing and editing circuits

Use the arrow keys and `Enter` in the main menu to choose the circuit editor, measurement mode, a blank circuit, or an editable example (voltage divider or BJT common-emitter).

- Move the orange cursor across the grid with the arrow keys. Press `8` to open the component menu, select an item with the arrows, then press `Enter`. Use `1` and `2` or `Tab` to cycle through components.
- Press `3` to rotate the selected component **before placing it**, then press `Enter`. The current orientation is shown at the top of the screen. Resistors, capacitors, and similar components connect between two grid points. BJT, MOSFET, and JFET symbols rotate with their terminals. The terminal guide at the bottom shows `B/G` (base/gate), `C/D` (collector/drain), `E/S` (emitter/source), and `L/U/R/D` (left/up/right/down). A transistor cannot be placed where there is not enough room for its terminals.
- To rotate an existing transistor, choose `SELECT`, move the cursor to its center, press `Enter` or `5` to open its properties, then press `3`. The symbol and its electrical terminals rotate together. If the next orientation cannot fit, the app explains why. You can also click the symbol with the touchpad to open its properties.
- To delete a component, move the cursor over it and press the calculator's `Del` key (the key labeled `Backspace`). You can also delete it from its properties page. If several components meet at one node, use left/right on the properties page to select the one you want. Press `9` to undo the most recent edit (up to 8 edits per session).
- On a properties page, use up/down to select a value and press `Enter` to edit it in the calculator's normal input field. Values such as `2.2k` or `10m` are accepted. Press `Enter` to save or `Esc` to cancel.
- Press `0` in the editor for direct measurements, `4` for the full report, `6` to set the AC frequency, and `7` for help. Press `Esc` to go back. In reports, use up/down to scroll and left/right to jump between pages. A `GROUND` component is required as the 0 V reference. `IN PROBE` and `OUT PROBE` select the nodes used for gain measurements.

## Direct measurements

After drawing a circuit and connecting ground, press `0` in the editor or choose **Measure DC or AC** from the main menu. The measurement menu offers:

1. **DC Voltage:** Choose the positive node, press `Enter`, then choose the negative node. The result is `V(+) − V(−)`. Choose ground as the negative node to measure a node voltage relative to 0 V.
2. **AC Voltage:** Choose the same two nodes. The result includes peak amplitude, RMS value, and phase at the selected frequency.
3. **DC Current:** Choose a component by name. The signed current is shown; a negative sign means the current flows opposite to the displayed reference direction.
4. **AC Current:** Choose a component to see peak, RMS, and phase. For a BJT, AC collector current is measured; the DC measurement also shows base current.
5. **Full Analysis Report:** Shows the full table of node voltages, currents, and device operating regions.

For resistors, capacitors, diodes, and sources, the reference current direction is from terminal `A` to terminal `B`. For BJTs it is from `C` to `E`; for MOSFETs/JFETs it is from `D` to `S`. If an AC measurement is zero, open the voltage/current source properties, enter a nonzero **AC peak** value, and set the frequency with `6`.

## Supported analysis

Components: resistors, capacitors, DC/AC voltage sources, DC/AC current sources, diodes, NPN BJTs, NMOS, JFETs, wires, and ground. The program finds the DC operating point from the drawn connections, then performs linear AC analysis around that point at the selected frequency. Results include node voltages, component currents and power, transistor operating regions, AC voltage/current magnitude and phase, and gain between the selected probe nodes. A warning is shown when the AC signal is too large for the small-signal approximation. Capacitors are open circuits for DC and have frequency-dependent impedance in AC.

## Model limitations

This is an educational circuit analyzer, not a full LTspice replacement. It does not provide transient simulation, automatic frequency sweeps, PNP/PMOS devices, inductors, dependent sources, or manufacturer SPICE models. The device models are simplified: an Ebers–Moll-style BJT model, square-law MOSFET/JFET models, and an exponential diode model. Warnings are shown for unsupported or out-of-range cases such as cutoff, MOSFET triode operation, or forward-biased JFET gates. The practical limits are 30 components and 32 independent variables. Floating nodes without a DC path cause an error instead of a misleading result.

## Community and support

- Ask questions or share feedback in [GitHub Discussions](https://github.com/alldasher/ti-nspire-circuit-lab/discussions).
- Report reproducible bugs through [GitHub Issues](https://github.com/alldasher/ti-nspire-circuit-lab/issues).

The Lua source and regression checks are included for development; they do not need to be transferred to the calculator. The app was checked with software tests and screen-layout previews. A final check on physical calculator hardware is still recommended because a TI calculator emulator was not available during development.
