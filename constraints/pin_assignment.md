# ZCU102 Pin Assignment — bsg_link_test_top ↔ Mini_Dice chip

Chip pad indices from `Mini_Dice/rtl/chip_top.sv`.

> **Channel width:** chip uses `CHANNEL_WIDTH = 16`. Instantiate FPGA top with
> `CHANNEL_WIDTH_P = 16`.

---

## Connector A — ASIC → FPGA (HPC0 JP1 ↔ HPC1 JP2)

Chip drives these; FPGA receives. Carries the chip's upstream TX bus and the
downstream credit return from the chip.


| Chip Signal   | Chip PAD | ZCU102 Package Pin | FPGA Port                     |
| ------------- | -------- | ------------------ | ----------------------------- |
| `up_clk`      | 15       |                    | `downstream_io_clk_i[0]`      |
| `up_valid`    | 14       |                    | `downstream_io_valid_i[0]`    |
| `up_data[0]`  | 22       |                    | `downstream_io_data_i[0][0]`  |
| `up_data[1]`  | 23       |                    | `downstream_io_data_i[0][1]`  |
| `up_data[2]`  | 20       |                    | `downstream_io_data_i[0][2]`  |
| `up_data[3]`  | 21       |                    | `downstream_io_data_i[0][3]`  |
| `up_data[4]`  | 18       |                    | `downstream_io_data_i[0][4]`  |
| `up_data[5]`  | 19       |                    | `downstream_io_data_i[0][5]`  |
| `up_data[6]`  | 16       |                    | `downstream_io_data_i[0][6]`  |
| `up_data[7]`  | 17       |                    | `downstream_io_data_i[0][7]`  |
| `up_data[8]`  | 28       |                    | `downstream_io_data_i[0][8]`  |
| `up_data[9]`  | 29       |                    | `downstream_io_data_i[0][9]`  |
| `up_data[10]` | 30       |                    | `downstream_io_data_i[0][10]` |
| `up_data[11]` | 31       |                    | `downstream_io_data_i[0][11]` |
| `up_data[12]` | 32       |                    | `downstream_io_data_i[0][12]` |
| `up_data[13]` | 33       |                    | `downstream_io_data_i[0][13]` |
| `up_data[14]` | 34       |                    | `downstream_io_data_i[0][14]` |
| `up_data[15]` | 35       |                    | `downstream_io_data_i[0][15]` |
| `dn_token`    | 10       |                    | `token_clk_i[0]`              |


---

## Connector B — FPGA → ASIC (HPC0 JP2 ↔ HPC1 JP1)

FPGA drives these; chip receives. Carries the FPGA's upstream TX bus, the
upstream credit return to the chip, and the chip's clock and reset.


| FPGA Port                        | ZCU102 Package Pin | Chip Signal   | Chip PAD |
| -------------------------------- | ------------------ | ------------- | -------- |
| `upstream_io_clk_r_o[0]`         |                    | `dn_clk`      | 8        |
| `upstream_io_valid_r_o[0]`       |                    | `dn_valid`    | 9        |
| `upstream_io_data_r_o[0][0]`     |                    | `dn_data[0]`  | 0        |
| `upstream_io_data_r_o[0][1]`     |                    | `dn_data[1]`  | 1        |
| `upstream_io_data_r_o[0][2]`     |                    | `dn_data[2]`  | 2        |
| `upstream_io_data_r_o[0][3]`     |                    | `dn_data[3]`  | 3        |
| `upstream_io_data_r_o[0][4]`     |                    | `dn_data[4]`  | 4        |
| `upstream_io_data_r_o[0][5]`     |                    | `dn_data[5]`  | 5        |
| `upstream_io_data_r_o[0][6]`     |                    | `dn_data[6]`  | 6        |
| `upstream_io_data_r_o[0][7]`     |                    | `dn_data[7]`  | 7        |
| `upstream_io_data_r_o[0][8]`     |                    | `dn_data[8]`  | 37       |
| `upstream_io_data_r_o[0][9]`     |                    | `dn_data[9]`  | 36       |
| `upstream_io_data_r_o[0][10]`    |                    | `dn_data[10]` | 39       |
| `upstream_io_data_r_o[0][11]`    |                    | `dn_data[11]` | 38       |
| `upstream_io_data_r_o[0][12]`    |                    | `dn_data[12]` | 41       |
| `upstream_io_data_r_o[0][13]`    |                    | `dn_data[13]` | 40       |
| `upstream_io_data_r_o[0][14]`    |                    | `dn_data[14]` | 43       |
| `upstream_io_data_r_o[0][15]`    |                    | `dn_data[15]` | 42       |
| `downstream_core_token_r_o[0]`   |                    | `token_clk`   | 12       |
| `chip_core_clk_o` *(add to top)* |                    | `core_clk`    | 44       |
| `chip_reset_o` *(add to top)*    |                    | `hard_reset`  | 45       |


---

## FPGA board inputs (ZCU102 sources, no chip connection)

These drive the FPGA only — clock oscillator, button, or switch on the ZCU102.


| FPGA Port                       | ZCU102 Package Pin | Note                       |
| ------------------------------- | ------------------ | -------------------------- |
| `core_clk_i`                    |                    | ZCU102 clock source        |
| `io_master_clk_i`               |                    | Tie to `core_clk_i` source |
| `rst_i`                         |                    | Button / switch            |
| `upstream_io_link_reset_i`      |                    | Button / switch            |
| `async_token_reset_i`           |                    | Button / switch            |
| `downstream_io_link_reset_i[0]` |                    | Button / switch            |


