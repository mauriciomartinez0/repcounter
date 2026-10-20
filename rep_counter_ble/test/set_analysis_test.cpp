// Host test for set_analysis.h: reads recordings written by set_analysis.py
// (16-bit mm/s², the firmware's format) and prints the analysis of each.
//
//   g++ -O2 -std=c++17 -I.. set_analysis_test.cpp -o set_analysis_test
//   ./set_analysis_test [-g grip_cm] recording.bin ...
//
// -g: how far taking the handle lifts the stack, as the app sends it.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "set_analysis.h"

static stack::Workspace workspace;

int main(int argc, char **argv) {
  int k = 1;
  float minRom = stack::MIN_ROM_M;
  if (argc > 2 && strcmp(argv[1], "-g") == 0) {
    minRom = stack::minRomForGrip((uint8_t)atoi(argv[2]));
    k = 3;
  }
  for (; k < argc; k++) {
    FILE *f = fopen(argv[k], "rb");
    if (!f) { printf("%s ERROR\n", argv[k]); continue; }
    std::vector<int16_t> samples;
    int16_t value;
    while (fread(&value, sizeof value, 1, f) == 1) samples.push_back(value);
    fclose(f);
    uint16_t a_b = stack::passB(samples.data(), samples.size(), workspace, minRom);
    uint16_t a_a = stack::passA(samples.data(), samples.size(), workspace, minRom);
    printf("%s %u %u\n", argv[k], a_a, a_b);
  }
  return 0;
}
