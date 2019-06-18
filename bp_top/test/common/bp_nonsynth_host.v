
module bp_nonsynth_host
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_be_pkg::*;
 import bp_be_rv64_pkg::*;
 import bp_cce_pkg::*;
 import bsg_noc_pkg::*;
 import bp_cfg_link_pkg::*;
 #(parameter bp_cfg_e cfg_p = e_bp_inv_cfg
   `declare_bp_proc_params(cfg_p)
   , localparam cce_mshr_width_lp = `bp_cce_mshr_width(num_lce_p, lce_assoc_p, paddr_width_p)
   `declare_bp_me_if_widths(paddr_width_p, cce_block_width_p, num_lce_p, lce_assoc_p, cce_mshr_width_lp)
   )
  (input clk_i
   , input reset_i

   , input [cce_mem_data_cmd_width_lp-1:0]         mem_data_cmd_i
   , input                                         mem_data_cmd_v_i
   , output logic                                  mem_data_cmd_yumi_o

   , output logic [mem_cce_resp_width_lp-1:0]      mem_resp_o
   , output logic                                  mem_resp_v_o
   , input                                         mem_resp_ready_i
   );

`declare_bp_me_if(paddr_width_p, cce_block_width_p, num_lce_p, lce_assoc_p, cce_mshr_width_lp);

// HOST I/O mappings
localparam host_dev_base_addr_gp     = 32'h03??_????;

// Host I/O mappings (arbitrarily decided for now)
//   Overall host controls 32'h0300_0000-32'h03FF_FFFF

localparam hprint_base_addr_gp = 32'h0300_0???;
localparam cprint_base_addr_gp = 32'h0300_1???;
localparam finish_base_addr_gp = 32'h0300_2???;

bp_cce_mem_data_cmd_s  mem_data_cmd_cast_i;

assign mem_data_cmd_cast_i = mem_data_cmd_i;

localparam lg_num_core_lp = `BSG_SAFE_CLOG2(num_core_p);

logic hprint_data_cmd_v;
logic cprint_data_cmd_v;
logic finish_data_cmd_v;

always_comb
  begin
    hprint_data_cmd_v = 1'b0;
    cprint_data_cmd_v = 1'b0;
    finish_data_cmd_v = 1'b0;

    unique
    casez (mem_data_cmd_cast_i.addr)
      hprint_base_addr_gp: hprint_data_cmd_v = mem_data_cmd_v_i; 
      cprint_base_addr_gp: cprint_data_cmd_v = mem_data_cmd_v_i;
      finish_base_addr_gp: finish_data_cmd_v = mem_data_cmd_v_i;
      default: begin end
    endcase
  end

logic [num_core_p-1:0] hprint_w_v_li;
logic [num_core_p-1:0] cprint_w_v_li;
logic [num_core_p-1:0] finish_w_v_li;

// Memory-mapped I/O is 64 bit aligned
localparam byte_offset_width_lp = 3;
wire [lg_num_core_lp-1:0] mem_data_cmd_core_enc =
  mem_data_cmd_cast_i.addr[byte_offset_width_lp+:lg_num_core_lp];

bsg_decode_with_v
 #(.num_out_p(num_core_p))
 hprint_data_cmd_decoder
  (.v_i(hprint_data_cmd_v)
   ,.i(mem_data_cmd_core_enc)
   
   ,.o(hprint_w_v_li)
   );

bsg_decode_with_v
 #(.num_out_p(num_core_p))
 cprint_data_cmd_decoder
  (.v_i(cprint_data_cmd_v)
   ,.i(mem_data_cmd_core_enc)

   ,.o(cprint_w_v_li)
   );

bsg_decode_with_v
 #(.num_out_p(num_core_p))
 finish_data_cmd_decoder
  (.v_i(finish_data_cmd_v)
   ,.i(mem_data_cmd_core_enc)

   ,.o(finish_w_v_li)
   );

logic [num_core_p-1:0] finish_r;
bsg_dff_reset
 #(.width_p(num_core_p))
 finish_accumulator
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.data_i(finish_r | finish_w_v_li)
   ,.data_o(finish_r)
   );

always_ff @(negedge clk_i)
  begin
    for (integer i = 0; i < num_core_p; i++)
      begin
        if (hprint_w_v_li[i] & mem_data_cmd_yumi_o)
          $display("[CORE%0x PRT] %x", i, mem_data_cmd_cast_i.data[0+:8]);
        if (cprint_w_v_li[i] & mem_data_cmd_yumi_o)
          $display("[CORE%0x PRT] %c", i, mem_data_cmd_cast_i.data[0+:8]);
        if (finish_w_v_li[i] & mem_data_cmd_yumi_o & ~mem_data_cmd_cast_i.data[0])
          $display("[CORE%0x FSH] PASS", i);
        if (finish_w_v_li[i] & mem_data_cmd_yumi_o & ~mem_data_cmd_cast_i.data[0])
          $display("[CORE%0x FSH] FAIL", i);
      end

    if (&finish_r)
      begin
        $display("All cores finished! Terminating...");
        $finish();
      end
  end

bp_mem_cce_resp_s mem_resp_lo;
logic mem_resp_ready_lo;
assign mem_data_cmd_yumi_o = mem_data_cmd_v_i & mem_resp_ready_lo;
bsg_one_fifo
 #(.width_p(mem_cce_resp_width_lp))
 mem_resp_buffer
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.data_i(mem_resp_lo)
   ,.v_i(mem_data_cmd_yumi_o)
   ,.ready_o(mem_resp_ready_lo)

   ,.data_o(mem_resp_o)
   ,.v_o(mem_resp_v_o)
   ,.yumi_i(mem_resp_ready_i & mem_resp_v_o)
   );

assign mem_resp_lo =
  {msg_type       : mem_data_cmd_cast_i.msg_type
   ,addr          : mem_data_cmd_cast_i.addr
   ,payload       : mem_data_cmd_cast_i.payload
   ,non_cacheable : mem_data_cmd_cast_i.non_cacheable
   ,nc_size       : mem_data_cmd_cast_i.nc_size
   };


endmodule : bp_nonsynth_host

