#include <iostream>
#include <fstream>
#include <cstdio>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <sys/types.h>

#include <xgboost/data.h>
#include <xgboost/c_api.h>

extern "C" {
  int predict(int *model, float *feature, int *nrow, int *nfea, const float *output);
}
