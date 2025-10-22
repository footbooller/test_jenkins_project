`timescale 1ns / 1ps
module lte_hw_acc_scrambler #(
    parameter IN_DATA_WIDTH = 1
)
(
    // --- Basic ---
    input  logic                         clk,
    input  logic                         ce,
    input  logic                         rstn,

    input  logic [3:0]                   sfn,        // start frame number
    
    // --- Input connector (AXIS_S) ---
    input [IN_DATA_WIDTH - 1 : 0]        s_data,     // data from tbcc to xor my data
    input                                s_valid,
    output                               s_ready,
    input                                in_sof,     // Start Of Frame
    input [7:0]                          in_lof,     // Length Of Frame

    input [4:0]                          cfg_addr,
    input [30:0]                         cfg_data,
    input                                cfg_wr,

    // --- Output connector (AXIS_M) ---
    output [IN_DATA_WIDTH - 1 : 0]       m_data,
    output                               m_valid,
    input                                m_ready,
    output                               out_sof,    // Start Of Frame
    output [7:0]                         out_lof     // Length Of Frame
);

    // вспомогательные регистры
    logic [30:0]                    x_data_1;
    logic [30:0]                    x_data_2;

    logic [19:0] [30:0]             cfg_reg;        // регистры конфигурации, куда будем записывать все subframes попарно: нечётные - x_1, чётные - x_2
    logic [7:0]                     counter;

    logic                           processing;     // флаг активной обработки кадра
    logic                           transfer;

    // логика для бита сначала фрейма
    logic [30:0]                    effective_x1;
    logic [30:0]                    effective_x2;

    assign effective_x1 = (transfer && in_sof) ? cfg_reg[2 * sfn] : x_data_1;
    assign effective_x2 = (transfer && in_sof) ? cfg_reg[2 * sfn + 1] : x_data_2;

    // для инициализации регистровой карты subframes 
    always @(posedge clk) begin
        if(!rstn) begin
            for (int i = 0; i < 20; i++) begin
                
                if (i % 2 == 0) begin
                    
                    cfg_reg [i] = {30'b0, 1'b1};

                end
                
                else if (i % 2 == 1) begin
                    
                    cfg_reg[i] = (i >> 2) << 9;

                end
            end
        end
        if(cfg_wr && !processing) begin
            cfg_reg[cfg_addr] <= cfg_data;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rstn) begin
            
            x_data_1    <= 31'b0;
            x_data_2    <= 31'b0;
            processing  <= 1'b0;
            counter     <= 8'b0;
            
        end else if(ce) begin

            if (transfer) begin

                if (in_sof) begin

                    x_data_1 <= {effective_x1[0] ^ effective_x1[3], effective_x1[30:1]};
                    x_data_2 <= {effective_x2[0] ^ effective_x2[1] ^ effective_x2[2] ^ effective_x2[3], effective_x2[30:1]};
                    counter <= in_lof - 8'd1;
                    processing <= 1'b1;

                end else if (processing) begin

                    x_data_1 <= {x_data_1[0] ^ x_data_1[3], x_data_1[30:1]};
                    x_data_2 <= {x_data_2[0] ^ x_data_2[1] ^ x_data_2[2] ^ x_data_2[3], x_data_2[30:1]};
                    counter <= counter - 8'd1;

                    if (counter == 8'd1) begin 
                        processing <= 1'b0;
                    end
                end
            end
        end

    end
    
    assign m_data   = s_data ^ (effective_x1[0] ^ effective_x2[0]);
    assign transfer = s_valid && s_ready;
    assign s_ready  = m_ready;
    assign m_valid  = s_valid;
    assign out_lof  = in_lof;
    assign out_sof  = in_sof;
        
endmodule
