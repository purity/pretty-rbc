
/* set RBX_DEBUG_DIR before starting rbx. pass the same directory to this program.
   delete rbx_read.txt and rbx_write.txt manually after debug session. */

/* g++ -Wall -c rbx_debug_terminal.cpp; g++ -o rbx_debug_terminal rbx_debug_terminal.o */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string>

uint32_t num_records = 0;

void rtrim(char* str) {   // don't use if strlen can equal 0
  while(*str) ++str;
  --str; *str = '\0';
}

bool numeric_string(char* str) {
  if(!*str) return false;
  while(*str) {
    if(!isdigit(*str)) return false;
    ++str;
  }
  return true;
}

void receive_debug_commands(const char* wfile) {
  FILE* wd;
  std::string str;
  char out[512];
  char ssz[32];
  size_t len_out;

  printf("[rdt] waiting for user input. press <enter> to poll for message\n");
  fgets(out, 512 - 4, stdin);

  rtrim(out);
  len_out = strlen(out);

  if(len_out != 0) {

    if((wd = fopen(wfile, "a")) == NULL) {
      printf("[rdt] failed to send command. fopen error.\n");
      return;
    }

    snprintf(ssz, 32 - 4, "%u\n", len_out);
    str += ssz;
    str += out;

    if(fwrite(str.c_str(), 1, str.size(), wd) < str.size()) {
      printf("[rdt] failed to send command. fwrite error.\n");
      fclose(wd);
      return;
    }

    fclose(wd);
    sleep(5);
  }
}

void poll_debug_file(const char* rfile, const char* wfile) {
  FILE* rd;
  uint32_t nth_record, sec_sleep = 15;
  int sz_record;
  char tmp[8192];

  while(1) {

    if((rd = fopen(rfile, "r")) == NULL) {
      printf("[rdt] unable to open rbx_write.txt. trying again.\n");
      sleep(sec_sleep);
      continue;
    }

    nth_record = 0;

    while(1) {

      if(fgets(tmp, 8192 - 4, rd) == NULL) {
        receive_debug_commands(wfile);
        break;
      }

      rtrim(tmp);

      if(!numeric_string(tmp)) {
        printf("[rdt] invalid size line (not numeric). nth_record: '%u'\n", nth_record);
        sleep(sec_sleep);
        break;
      }

      sz_record = atoi(tmp);
      if(sz_record <= 0) continue;

      if(sz_record > 8192 - 4) {
        printf("[rdt] sz_record is too high. nth_record: '%u'\n", nth_record);
        sleep(sec_sleep);
        break;
      }

      tmp[sz_record] = '\0';
      if(fread(tmp, 1, (size_t)sz_record, rd) < (size_t)sz_record) {
        printf("[rdt] failed to read record. nth_record: '%u'\n", nth_record);
        sleep(sec_sleep);
        break;
      }

      if(nth_record >= num_records) {
        printf(tmp);
        ++num_records;
      }

      ++nth_record;
    }

    fclose(rd);
  }
}

int main(int argc, char** argv) {
  std::string dir, rfile, wfile;

  if(argc != 2) {
    printf("USAGE: app dir\n");
    return 1;
  }

  dir = argv[1];

  if(dir[dir.size() - 1] != '/') {
    dir.push_back('/');
  }

  rfile = dir;
  rfile += "rbx_write.txt";
  wfile = dir;
  wfile += "rbx_read.txt";

  poll_debug_file(rfile.c_str(), wfile.c_str());

  return 0;
}

