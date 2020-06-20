
library(h2o)
library(xgboost)
library(Matrix)
library(data.table)

library(ggplot2)
library(dplyr)
library(openxlsx)

h2o.init()

options(java.parameters = "-Xmx8g")
memory.limit(size=10000000000024)   #max bellek kullanımı 
Sys.setenv("R_MAX_VSIZE"=64000000000)



#################################################################
###################     Data Extraction       ###################
#################################################################

# Read in csv files
MAIN_TABLE <- read.table("C:\\Users\\DS�\\Desktop\\ar_proj_.csv", 
                         header = TRUE,
                         stringsAsFactors = FALSE,
                         sep = ";")


MAIN_TABLE<- as.data.table(MAIN_TABLE)
str(MAIN_TABLE)
colnames(MAIN_TABLE)

#check if there are variables that have the same min and max values or not.
OZET <- summary(MAIN_TABLE)
OZET<- as.data.table(OZET)

#remove variables that have the same minimum and 
#maximum values to avoid from "standard deviation is equal to zero" error. 
MAIN_TABLE[,  c("Durulama_Sayisi") := NULL] 
MAIN_TABLE$Durulama_Sayisi <- NULL

###ASSET_CORR_ANL.png

#+++++++++++++++++++++++++
# Computing of correlation matrix
#+++++++++++++++++++++++++
# Required package : corrplot
# x : matrix
# type: possible values are "lower" (default), "upper", "full" or "flatten";
#display lower or upper triangular of the matrix, full  or flatten matrix.
# graph : if TRUE, a correlogram or heatmap is plotted
# graphType : possible values are "correlogram" or "heatmap"
# col: colors to use for the correlogram
# ... : Further arguments to be passed to cor or cor.test function
# Result is a list including the following components :
# r : correlation matrix, p :  p-values
# sym : Symbolic number coding of the correlation matrix

your_data <- MAIN_TABLE
# name
work="ASSET_COR_"

rquery.cormat<-function(x,
                        type=c('lower', 'upper', 'full', 'flatten'),
                        graph=TRUE,
                        graphType=c("correlogram", "heatmap"),
                        col=NULL, ...)
{ 
  # Result Location
  setwd("C:\\Users\\DS�\\Desktop\\arcelik_proje")
  
  library(corrplot)
  # Helper functions
  #+++++++++++++++++
  # Compute the matrix of correlation p-values
  cor.pmat <- function(x, ...) {
    mat <- as.matrix(x)
    n <- ncol(mat)
    p.mat<- matrix(NA, n, n)
    diag(p.mat) <- 0
    for (i in 1:(n - 1)) {
      for (j in (i + 1):n) {
        tmp <- cor.test(mat[, i], mat[, j], ...)
        p.mat[i, j] <- p.mat[j, i] <- tmp$p.value
      }
    }
    colnames(p.mat) <- rownames(p.mat) <- colnames(mat)
    p.mat
  }
  # Get lower triangle of the matrix
  getLower.tri<-function(mat){
    upper<-mat
    upper[upper.tri(mat)]<-""
    mat<-as.data.frame(upper)
    mat
  }
  # Get upper triangle of the matrix
  getUpper.tri<-function(mat){
    lt<-mat
    lt[lower.tri(mat)]<-""
    mat<-as.data.frame(lt)
    mat
  }
  # Get flatten matrix
  flattenCorrMatrix <- function(cormat, pmat) {
    ut <- upper.tri(cormat)
    data.frame(
      row = rownames(cormat)[row(cormat)[ut]],
      column = rownames(cormat)[col(cormat)[ut]],
      cor  =(cormat)[ut],
      p = pmat[ut]
    )
  }
  # Define color
  if (is.null(col)) {
    col <- colorRampPalette(
      c("#67001F", "#B2182B", "#D6604D", "#F4A582",
        "#FDDBC7", "#FFFFFF", "#D1E5F0", "#92C5DE", 
        "#4393C3", "#2166AC", "#053061"))(200)
    col<-rev(col)
  }
  
  # Correlation matrix
  cormat<-signif(cor(x, use = "complete.obs", ...),2)
  pmat<-signif(cor.pmat(x, ...),2)
  # Reorder correlation matrix
  ord<-corrMatOrder(cormat, order="hclust")
  cormat<-cormat[ord, ord]
  pmat<-pmat[ord, ord]
  # Replace correlation coeff by symbols
  sym<-symnum(cormat, abbr.colnames=FALSE)
  
  #arrange size according to your data
  png(height=5000, width=5000, pointsize=40, file="ASSET_CORR_ANL.png")
  
  # Correlogram
  if(graph & graphType[1]=="correlogram"){
    corrplot(cormat, type=ifelse(type[1]=="flatten", "lower", type[1]),
             tl.col="black", tl.srt=45,col=col,...)
  }
  else if(graphType[1]=="heatmap")
    heatmap(cormat, col=col, symm=TRUE)
  # Get lower/upper triangle
  if(type[1]=="lower"){
    cormat<-getLower.tri(cormat)
    pmat<-getLower.tri(pmat)
  }
  else if(type[1]=="upper"){
    cormat<-getUpper.tri(cormat)
    pmat<-getUpper.tri(pmat)
    sym=t(sym)
  }
  else if(type[1]=="flatten"){
    cormat<-flattenCorrMatrix(cormat, pmat)
    pmat=NULL
    sym=NULL
  }
  list(r=cormat, p=pmat, sym=sym)
  dev.off()
  
}

#correlation matrix exp
corr_matrix<-rquery.cormat(your_data)


#################################################################
#############    Create train/test/oot samples  #################
################################################################# 

DT <- read.table("C:\\Users\\DS�\\Desktop\\ar_proj_.csv", 
                 header = TRUE,
                 stringsAsFactors = FALSE,
                 sep = ";")


DT<- as.data.table(DT)

colnames(DT)


#split 75-25

modelDevSeq <- sample(1:nrow(DT), round(nrow(DT)*0.75) , replace = FALSE)
modelDevSample  <- DT[modelDevSeq]
modelTestSample <- DT[!modelDevSeq] #dropping modelDevSeq table from DT and then getting modelTestSample

#data �oklama ve korelasyonu 0,80-1 aras� de�i�kenlerin ��kar�lmas�

vars_to_remove<-c("Durulama_Sayisi",
                  "SY1_Devir_.rpm.",
                  "X1D_Devir_.rpm.",
                  "X2D_Devir_.rpm.",
                  "X3D_Devir_.rpm.",
                  "Deterjan_Miktar�..gr.",
                  "X3D_MHY_ED",
                  "SY1_ED",#buraya kadar �oklama
                  "Numune_1_.Relakse_Sonrasi_.En_1",
                  "Numune_1_.Relakse_Sonrasi_.En_2",
                  "Numune_1_.Relakse_Sonrasi_.En_3",
                  "Numune_1_Relakse_Sonrasi_Boy_1" ,
                  "Numune_1_Relakse_Sonrasi_Boy_2" ,
                  "Numune_1_Relakse_Sonrasi_Boy_3" ,
                  "I_Sure_.sn.",
                  "I_Tset_.C.",
                  "X1D_MHY_ED",
                  "X3D_Sure_.sn.",
                  "X1D_Su_Mik_.lt.",
                  "X2D_Su_Mik_.lt.",
                  "X2D_Sure_.sn.",
                  "Tambur_Hacmi_.lt."
          )

colnames(DT)


modelDevSample[,  c( vars_to_remove) := NULL]
modelTestSample[,  c( vars_to_remove) := NULL]

#################################################################
####   Create the (sparse) model matrices for all samples   #####
################################################################# 

#strain <- sparse.model.matrix(Cikis_Alan_Ortalama ~ .- 1  , data = modelDevSample)

model_formula <- as.formula(Cikis_Alan_Ortalama ~ . - 1) #TARGET'I ÇIKARMAK İÇİN

sparse_train <- sparse.model.matrix(model_formula, data = modelDevSample)
label_train <- modelDevSample$Cikis_Alan_Ortalama
dense_train <- xgb.DMatrix(data = sparse_train,  label = label_train)

sparse_test <- sparse.model.matrix(model_formula, data = modelTestSample)
label_test <- modelTestSample$Cikis_Alan_Ortalama
dense_test <- xgb.DMatrix(data = sparse_test, label = label_test)


#bst <- xgboost(data = dense_train, max_depth = 2, nthread =2, nrounds = 2, verbose = 0) ->> verbose
gc()
class(sparse_train) #dgCMatrix
dim(sparse_train) #dimension
head(sparse_train)
# ilk önce sparce matrix yapısına göre değişkenler düzenlenir, daha sonrasında 
# bu düzenlenen değişkenlerin label'i belirlenir yani target değişkeni..
# daha sonrasında Dmatrix de bu matris biçimi model biçimi olarak birleştirilir. 

searchGridSubCol <- expand.grid(gamma = c(0,1), #default value set to 0.
                                max_depth = c(6,5), #¦¦¦¦ the default value is set to 6. 
                                lambda = c(0.2,0.4, 0.5),
                                eta = c(0.1,0.2,0.3) #default value is set to 0.3 
                                #grid search alg araştır
                                
)

ntrees <- 100


rmseErrorsHyperparameters <- apply(searchGridSubCol, 1, function(parameterList){
  #Extract Parameters to test
  currentGamma <- parameterList[["gamma"]]
  currentDepth <- parameterList[["max_depth"]]
  currentLambda <- parameterList[["lambda"]]
  currentEta <- parameterList[["eta"]]
  xgboostModelCV <- xgb.cv(data =  dense_train,
                           nrounds = ntrees,
                           nfold = 5,
                           showsd = F,
                           print_every_n = 10, #her 10 tanede bir öğren, her 10 dallanmada öğren.
                           "eval_metric" = "rmse",
                           "objective"   = "reg:linear",
                           "booster" = "dart",
                           "gamma" = currentGamma,
                           "eta" = currentEta,
                           "lambda" = currentLambda,
                           "max.depth" = currentDepth,
                           "seed" = 123456,
                           maximize = TRUE)
  
  xvalidationScores <- as.data.table(xgboostModelCV$evaluation_log)
  rmse <- tail(xvalidationScores$test_rmse_mean, 1)
  trmse <- tail(xvalidationScores$sparse_train_rmse_mean,1)
  output <- c(rmse, trmse, currentGamma,currentLambda , currentDepth, currentEta)})


output <- as.data.table(t(rmseErrorsHyperparameters))
varnames <- c("Test RMSE",  "currentGamma","currentLambda",  "currentDepth",  "currentEta")
names(output) <- varnames
head(output) 
#output'u bulurken her bir verilen parametre için bir xgb modeli oluşturup rmse(root mean absolute error) değerini buldu. Testteki hata sonucu en az çıkan modeli seçicez. 
#
setwd("D:\\grid_search.")
#
write.xlsx(output, file = 'GridSearchAlgorithm_4.xlsx') #testin min olduğu


xgboost_params <- list(
  objective   = "reg:linear", #lineer regresyon 
  booster="dart",
  eval_metric = "rmse"
)



mod_xgb_dart <- xgb.cv(
  params = xgboost_params, 
  nrounds = 100,
  prediction = TRUE, 
  data = dense_train, 
  nfold = 10, 
  showsd = FALSE, 
  maximize = FALSE,
  early_stopping_rounds = 30,
  max.depth=6,
  gamma = 1,
  eta = 0.3,
  lambda = 0.4,
  print_every_n = 1
)

#outputtaki en az sonucu seçtik. ve onun parametrelerini gamma, max_depth, eta ve lamda değerlerini yazıp o oluşturulan modeli seçtik.

best_iteration = mod_xgb_dart$best_iteration


mod_xgb_dart_best <- xgboost(
  params = xgboost_params, 
  data = dense_train, 
  nrounds = best_iteration, 
  showsd = FALSE, 
  maximize = FALSE,
  max.depth=6,
  gamma = 1,
  eta = 0.3,
  lambda = 0.4,
  print_every_n = 50
)

importance_XGB  <- xgb.importance(feature_names = dimnames(sparse_train)[[2]],model = mod_xgb_dart_best)

#################################################################
###########        PREDICTION WITH FINAL MODEL       ############
#################################################################

#predict with the best trained xgboost model

pred_vect_dev_xgboost   <- predict(object = mod_xgb_dart_best, newdata = dense_train)
pred_vect_test_xgboost  <- predict(object = mod_xgb_dart_best, newdata = dense_test)



DT_PRED_S <- rbindlist(
  use.names = TRUE, 
  fill = TRUE, 
  l = list(
    data.table(sample = "dev", modelDevSample, predicted_CAO_xgb = pred_vect_dev_xgboost),
    data.table(sample = "test",modelTestSample, predicted_CAO_xgb = pred_vect_test_xgboost
    )
  ))

#dbWriteTable(jdbcConnection,name=paste("YKB_ASSET_",segment_name,"RESULTS_4",sep=""),DT_PRED_S)


colnames(DT)

#train data
absErrorDev_TargetvsEstimated_xgb <-  mean(abs(DT_PRED_S[DT_PRED_S$sample == "dev" ,Cikis_Alan_Ortalama] - DT_PRED_S[DT_PRED_S$sample == "dev",predicted_CAO_xgb]))
mapeErrorDev_TargetvsEstimated_xgb <-  mean(abs(DT_PRED_S[DT_PRED_S$sample == "dev",Cikis_Alan_Ortalama] - DT_PRED_S[DT_PRED_S$sample == "dev" ,predicted_CAO_xgb])/abs(DT_PRED_S[DT_PRED_S$sample == "dev" ,Cikis_Alan_Ortalama]))


# test data
absErrorTest_TargetvsEstimated_xgb <-  mean(abs(DT_PRED_S[DT_PRED_S$sample == "test" ,Cikis_Alan_Ortalama] - DT_PRED_S[DT_PRED_S$sample == "test",predicted_CAO_xgb]))
mapeErrorTest_TargetvsEstimated_xgb <-  mean(abs(DT_PRED_S[DT_PRED_S$sample == "test",Cikis_Alan_Ortalama] - DT_PRED_S[DT_PRED_S$sample == "test",predicted_CAO_xgb])/abs(DT_PRED_S[DT_PRED_S$sample == "test",Cikis_Alan_Ortalama]))


col0 = c(absErrorDev_TargetvsEstimated_xgb, absErrorTest_TargetvsEstimated_xgb)
col1 = c(mapeErrorDev_TargetvsEstimated_xgb, mapeErrorTest_TargetvsEstimated_xgb)
col2 = c("Train", "Test")
performance_fulllist_xgb = data.frame(col2, col0,col1)
names(performance_fulllist_xgb) = c("Sample", "Target_vs_Estimated_MAE", "Target_vs_Estimated_MAPE")
rm(col0,col1,col2)



ggplot(data = filter(DT_PRED_S,sample == "test"),aes(x=Cikis_Alan_Ortalama, y=predicted_CAO_xgb ))+
  geom_point(alpha=0.5,size=1)+
  geom_smooth()+
  scale_x_log10()+scale_y_log10()+ #grafi�i daralt�yo.
  geom_abline(aes(slope=1,intercept=0),colour='red')

# Result Location
setwd("C:\\Users\\DS�\\Desktop\\arcelik_proje")

ggsave(paste("Test_xgboost2",".png"),width =5,height=5)


ggplot(data = filter(DT_PRED_S,sample == "dev"),aes(x=Cikis_Alan_Ortalama, y=predicted_CAO_xgb ))+
  geom_point(alpha=0.5,size=1)+
  geom_smooth()+
  scale_x_log10()+scale_y_log10()+
  geom_abline(aes(slope=1,intercept=0),colour='red')


ggsave(paste("Dev_xgboost2",".png"),width =5,height=5)


########################
#SUNUM ���N AYARLANMI� KISIM, BURADA AMA� SUNUMDA BEL�RTMEK �ZERE MODELDEK� MODEL� �NEML� DERECEDE ETKILEYEN DE���KENLER� BULUP 
#DAHA SONRASINDA BU DE���KENLER� VARLIK TAHM�NLEMES�YLE ANALIZ ETMEK, G�RSELLE�T�RMEK

important_vars <- importance_XGB[,1:2]
important_vars <- important_vars %>% mutate(cumulativeGain = cumsum(Gain))
important_vars <- important_vars[important_vars$cumulativeGain <= 1,1] 




ggplot(data= filter(importance_XGB,Gain>1),aes(x=importance_XGB$Feature,y=importance_XGB$Gain  ))+
  geom_bar(stat = "identity")
#arrange size according to your data
png(height=10000, width=10000, pointsize=2, file="Feature_Imp.png")


importance_XGB2 <- arrange(importance_XGB, Gain)

importance_XGB2$Feature <- factor(importance_XGB2$Feature, levels = importance_XGB2$Feature)


ggplot(filter(importance_XGB2,Gain>0.012), aes(Feature, Gain) )+ 
  geom_col() + 
  coord_flip()+
  geom_bar(stat = "identity",fill="dodgerblue")

ggsave(paste("Test_xgboost2_FEA_IMP",".png"),width =5,height=5)