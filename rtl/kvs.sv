module kvs #(
    parameter KEY_WIDTH  = 16,
    parameter VAL_WIDTH  = 32,
    parameter INDEX_BITS = 5
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  req_valid,
    input  logic [1:0]            opcode,
    input  logic [KEY_WIDTH-1:0]  key_in,
    input  logic [VAL_WIDTH-1:0]  val_in,
    output logic                  resp_valid,
    output logic                  hit,
    output logic [VAL_WIDTH-1:0]  val_out
);
    localparam NUM_SETS = 1 << INDEX_BITS;

    logic                  req_valid_r;
    logic [1:0]            opcode_r;
    logic [KEY_WIDTH-1:0]  key_r;
    logic [VAL_WIDTH-1:0]  val_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_valid_r <= 1'b0; opcode_r <= 2'b00; key_r <= '0; val_r <= '0;
        end else begin
            req_valid_r <= req_valid; opcode_r <= opcode; key_r <= key_in; val_r <= val_in;
        end
    end

    logic                 valid_w0 [0:NUM_SETS-1], valid_w1 [0:NUM_SETS-1];
    logic [KEY_WIDTH-1:0] tag_w0   [0:NUM_SETS-1], tag_w1   [0:NUM_SETS-1];
    logic [VAL_WIDTH-1:0] data_w0  [0:NUM_SETS-1], data_w1  [0:NUM_SETS-1];
    logic                 lru      [0:NUM_SETS-1];

    logic [INDEX_BITS-1:0] set_idx, idx_s1;
    logic                  eff_v0, eff_v1, eff_lru, m0_s1, m1_s1;
    logic [KEY_WIDTH-1:0]  eff_t0, eff_t1, key_s1;
    logic                  valid_s1, m0_reg, m1_reg, evict_w0_s1;
    logic [1:0]            op_s1;
    logic [VAL_WIDTH-1:0]  val_s1;

    assign set_idx = key_r[INDEX_BITS-1:0] ^ key_r[2*INDEX_BITS-1:INDEX_BITS] ^ key_r[KEY_WIDTH-1:KEY_WIDTH-INDEX_BITS];

    always_comb begin
        eff_v0 = valid_w0[set_idx]; eff_v1 = valid_w1[set_idx];
        eff_t0 = tag_w0[set_idx];   eff_t1 = tag_w1[set_idx];
        eff_lru = lru[set_idx];

        if (valid_s1 && (idx_s1 == set_idx)) begin
            case (op_s1)
                2'b01: begin
                    if (m0_reg) eff_lru = 1'b1; else if (m1_reg) eff_lru = 1'b0;
                end
                2'b10: begin
                    if (m0_reg) eff_lru = 1'b1; else if (m1_reg) eff_lru = 1'b0;
                    else if (evict_w0_s1) begin eff_v0 = 1'b1; eff_t0 = key_s1; eff_lru = 1'b1; end
                    else                  begin eff_v1 = 1'b1; eff_t1 = key_s1; eff_lru = 1'b0; end
                end
                2'b11: begin
                    if (m0_reg) begin eff_v0 = 1'b0; eff_lru = 1'b0; end
                    else if (m1_reg) begin eff_v1 = 1'b0; eff_lru = 1'b1; end
                end
                default: ;
            endcase
        end
        m0_s1 = eff_v0 && (eff_t0 == key_r);
        m1_s1 = eff_v1 && (eff_t1 == key_r);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 0; op_s1 <= 0; idx_s1 <= 0; key_s1 <= 0; val_s1 <= 0;
            m0_reg <= 0; m1_reg <= 0; evict_w0_s1 <= 0;
        end else begin
            valid_s1 <= req_valid_r && (opcode_r != 2'b00);
            op_s1 <= opcode_r; idx_s1 <= set_idx; key_s1 <= key_r; val_s1 <= val_r;
            m0_reg <= m0_s1; m1_reg <= m1_s1;
            evict_w0_s1 <= (!eff_v0 || (eff_v1 && !eff_lru));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 0; hit <= 0; val_out <= 0;
            for (int i = 0; i < NUM_SETS; i++) begin
                valid_w0[i] <= 0; valid_w1[i] <= 0; lru[i] <= 0;
            end
        end else begin
            resp_valid <= valid_s1; hit <= 0; val_out <= 0;
            if (valid_s1) begin
                case (op_s1)
                    2'b01: begin
                        if (m0_reg)      begin hit <= 1; val_out <= data_w0[idx_s1]; lru[idx_s1] <= 1; end
                        else if (m1_reg) begin hit <= 1; val_out <= data_w1[idx_s1]; lru[idx_s1] <= 0; end
                    end
                    2'b10: begin
                        if (m0_reg)      begin data_w0[idx_s1] <= val_s1; lru[idx_s1] <= 1; end
                        else if (m1_reg) begin data_w1[idx_s1] <= val_s1; lru[idx_s1] <= 0; end
                        else if (evict_w0_s1) begin
                            valid_w0[idx_s1] <= 1; tag_w0[idx_s1] <= key_s1; data_w0[idx_s1] <= val_s1; lru[idx_s1] <= 1;
                        end else begin
                            valid_w1[idx_s1] <= 1; tag_w1[idx_s1] <= key_s1; data_w1[idx_s1] <= val_s1; lru[idx_s1] <= 0;
                        end
                    end
                    2'b11: begin
                        if (m0_reg)      begin valid_w0[idx_s1] <= 0; lru[idx_s1] <= 0; end
                        else if (m1_reg) begin valid_w1[idx_s1] <= 0; lru[idx_s1] <= 1; end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
