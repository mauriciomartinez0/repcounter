// Host test for set_analysis.h: reads recordings written by set_analysis.py
// (16-bit mm/s², the firmware's format) and prints the analysis of each.
//
//   g++ -O2 -std=c++17 -I.. set_analysis_test.cpp -o set_analysis_test
//   ./set_analysis_test [-s sensitivity] [-l] recording.bin ...
//
// Prints "file passA passB". With -l, also the live counter over the
// recording, with the reference from its first second: "file passA passB live".
// -s: the app's sensitivity, 0–100 (50 by default).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "set_analysis.h"

static stack::Workspace workspace;

int main(int argc, char **argv) {
  int k = 1;
  bool live = false;
  stack::Tuning tuning = stack::TUNING_DEFAULT;
  if (argc > k + 1 && strcmp(argv[k], "-s") == 0) {
    tuning = stack::tuningFor((uint8_t)atoi(argv[k + 1]));
    k += 2;
  }
  if (argc > k && strcmp(argv[k], "-l") == 0) {
    live = true;
    k++;
  }
  for (; k < argc; k++) {
    FILE *f = fopen(argv[k], "rb");
    if (!f) { printf("%s ERROR\n", argv[k]); continue; }
    std::vector<int16_t> samples;
    int16_t value;
    while (fread(&value, sizeof value, 1, f) == 1) samples.push_back(value);
    fclose(f);
    uint16_t l = 0;
    if (live) {
      uint32_t refLen = samples.size() < 104 ? samples.size() : 104;
      float ref = 0.0f;
      for (uint32_t i = 0; i < refLen; i++) ref += samples[i];
      ref = refLen ? ref / refLen : 0.0f;
      stack::StackCounter counter;
      counter.tuning = tuning;
      for (uint32_t i = 0; i < samples.size(); i++)
        counter.update((samples[i] - ref) / (1000.0f * stack::GRAVITY), (uint32_t)(i * 1000.0f / stack::FS));
      l = counter.reps;
    }
    uint16_t a_b = stack::passB(samples.data(), samples.size(), workspace, tuning);
    uint16_t a_a = stack::passA(samples.data(), samples.size(), workspace, tuning);
    if (live) printf("%s %u %u %u\n", argv[k], a_a, a_b, l);
    else printf("%s %u %u\n", argv[k], a_a, a_b);
  }
  return 0;
}
