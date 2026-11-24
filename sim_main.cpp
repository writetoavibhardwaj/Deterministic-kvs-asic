#include <iostream>
#include <random>
#include <cstdint>
#include "Vkvs.h"
#include "verilated.h"

struct GoldenKVS {
    bool valid0[32] = {}, valid1[32] = {}, lru[32] = {};
    uint16_t tag0[32] = {}, tag1[32] = {};
    uint32_t data0[32] = {}, data1[32] = {};
    uint8_t idx(uint16_t k) { return (k & 0x1F) ^ ((k >> 5) & 0x1F) ^ ((k >> 11) & 0x1F); }
    void step(uint8_t op, uint16_t k, uint32_t v, bool &hit, uint32_t &val_out) {
        uint8_t s = idx(k);
        bool m0 = valid0[s] && (tag0[s] == k), m1 = valid1[s] && (tag1[s] == k);
        hit = false; val_out = 0;
        if (op == 1) {
            if (m0) { hit = true; val_out = data0[s]; lru[s] = 1; }
            else if (m1) { hit = true; val_out = data1[s]; lru[s] = 0; }
        } else if (op == 2) {
            if (m0) { data0[s] = v; lru[s] = 1; }
            else if (m1) { data1[s] = v; lru[s] = 0; }
            else if (!valid0[s] || (valid1[s] && !lru[s])) { valid0[s] = 1; tag0[s] = k; data0[s] = v; lru[s] = 1; }
            else { valid1[s] = 1; tag1[s] = k; data1[s] = v; lru[s] = 0; }
        } else if (op == 3) {
            if (m0) { valid0[s] = 0; lru[s] = 0; }
            else if (m1) { valid1[s] = 0; lru[s] = 1; }
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vkvs* dut = new Vkvs; GoldenKVS ref; std::mt19937 rng(42);
    dut->clk = 0; dut->rst_n = 0; dut->req_valid = 0;
    for (int i = 0; i < 4; i++) { dut->clk ^= 1; dut->eval(); }
    dut->rst_n = 1;
    uint64_t gets = 0, puts = 0, dels = 0, hits = 0;
    uint8_t op_d1 = 0, op_d2 = 0; bool hit_d1 = 0, hit_d2 = 0; uint32_t val_d1 = 0, val_d2 = 0;
    for (int c = 0; c < 1000000; c++) {
        uint8_t op = (rng() % 3) + 1; uint16_t key = rng() % 64; uint32_t val = rng();
        dut->req_valid = 1; dut->opcode = op; dut->key_in = key; dut->val_in = val;
        dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval();
        if (c >= 2 && op_d2 == 1) {
            gets++; if (hit_d2) hits++;
            if ((bool)dut->hit != hit_d2 || (hit_d2 && dut->val_out != val_d2)) {
                std::cerr << "MISMATCH at cycle " << c << "\n"; return 1;
            }
        }
        bool exp_hit = false; uint32_t exp_val = 0;
        ref.step(op, key, val, exp_hit, exp_val);
        op_d2 = op_d1; hit_d2 = hit_d1; val_d2 = val_d1;
        op_d1 = op; hit_d1 = exp_hit; val_d1 = exp_val;
        if (op == 2) puts++; else if (op == 3) dels++;
    }
    std::cout << "PASS: 1000000 input-registered 2-stage cycles verified! (Hits: " << hits << ")\n";
    delete dut; return 0;
}
