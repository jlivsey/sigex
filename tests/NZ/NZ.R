#########################################
###  Script for Daily Immigration Data
#########################################

## wipe
rm(list=ls())

library(devtools)

# suppose directory is set to where sigex is located, e.g.
#setwd("C:\\Users\\neide\\Documents\\GitHub\\sigex")
load_all(".")
root.dir <- getwd()
setwd(paste(root.dir,"/tests/NZ",sep=""))


######################
### Part I: load data

# automatic: raw data

# processing

n.months <- dim(imm)[1]/32
imm <- imm[-seq(1,n.months)*32,]	# strip out every 32nd row (totals)
imm <- matrix(imm[imm != 0],ncol=6) # strip out 31st False days

# enter regressors
NZregs <- read.table(paste(root.dir,"/data/NZregressors.txt",sep=""))


#############################################################
### Part II: Metadata Specifications and Exploratory Analysis

start.date <- c(9,1,1997)
end.date <- day2date(dim(imm)[1]-1,start.date)
#end.date <- c(7,31,2012)
period <- 365

# calendar calculations
start.day <- date2day(start.date[1],start.date[2],start.date[3])
end.day <- date2day(end.date[1],end.date[2],end.date[3])
begin <- c(start.date[3],start.day)
end <- c(end.date[3],end.day)

## create ts object and plot
dataALL.ts <- sigex.load(imm,begin,period,c("NZArr","NZDep","VisArr","VisDep","PLTArr","PLTDep"),TRUE)


#############################
## select span and transforms

## first series with log transform
transform <- "log"
aggregate <- FALSE
subseries <- 1
range <- NULL
dataONE.ts <- sigex.prep(dataALL.ts,transform,aggregate,subseries,range,TRUE)


#######################
## spectral exploratory

## levels
par(mfrow=c(1,1))
for(i in 1:length(subseries))
{
  sigex.specar(dataONE.ts,FALSE,i,7)
}
dev.off()

## growth rates
par(mfrow=c(1,1))
for(i in 1:length(subseries))
{
  sigex.specar(dataONE.ts,TRUE,i,7)
}
dev.off()


###########################
## embed as a weekly series

first.day <- 1
data.ts <- sigex.daily2weekly(dataONE.ts,first.day,start.date)
plot(data.ts)



###############################
### Part III: Model Declaration

N <- dim(data.ts)[2]
T <- dim(data.ts)[1]

##########################
## Load holiday regressors
##
## NOTES: easter is based on Easter day and day before Easter
##        school1 is beginning of first school holiday,
##          with window for day of and day after.
##        School2 and school3 are analogous for 2nd and 3rd holidays
##        school1e is end of first school holiday,
##          with window for day of and day before.
##        School2e and school3e are analogous for 2nd and 3rd holidays

easter.reg <- NZregs[,1]
school1.reg <- NZregs[,2]
school1e.reg <- NZregs[,3]
school2.reg <- NZregs[,4]
school2e.reg <- NZregs[,5]
school3.reg <- NZregs[,6]
school3e.reg <- NZregs[,7]

###########################
## Embed holiday regressors

easter.reg <- sigex.daily2weekly(easter.reg,first.day,start.date)
school1.reg <- sigex.daily2weekly(school1.reg,first.day,start.date)
school1e.reg <- sigex.daily2weekly(school1e.reg,first.day,start.date)
school2.reg <- sigex.daily2weekly(school2.reg,first.day,start.date)
school2e.reg <- sigex.daily2weekly(school2e.reg,first.day,start.date)
school3.reg <- sigex.daily2weekly(school3.reg,first.day,start.date)
school3e.reg <- sigex.daily2weekly(school3e.reg,first.day,start.date)

# replace ragged NA with zero
easter.reg[is.na(easter.reg)] <- 0
school1.reg[is.na(school1.reg)] <- 0
school1e.reg[is.na(school1e.reg)] <- 0
school2.reg[is.na(school2.reg)] <- 0
school2e.reg[is.na(school2e.reg)] <- 0
school3.reg[is.na(school3.reg)] <- 0
school3e.reg[is.na(school3e.reg)] <- 0


##############
## Basic Model

ar.fit <- ar.yw(diff(data.ts[2:(T-1),]))
p.order <- ar.fit$order
par.yw <- aperm(ar.fit$ar,c(2,3,1))
covmat.yw <- getGCD(ar.fit$var.pred,2)
var.out <- var.par2pre(par.yw)
psi.init <- as.vector(c(covmat.yw[[1]][2,1],log(covmat.yw[[2]]),
                        var.out,colMeans(diff(ts(ndc[2:T,])))))



## preliminary analysis
imm.acf <- acf(diff(data.ts[2:(T-1),]),type="covariance",plot=FALSE,lag.max=53)$acf
phi.seas <- imm.acf[53,,] %*% solve(imm.acf[1,,])
dataSEAS.ts <- ts(matrix(0,nrow=(T-54),ncol=7),start=start(data.ts),frequency=52)
for(t in 54:(T-1))
{ dataSEAS.ts[t-53,] <- data.ts[t,] - phi.seas %*% data.ts[t-52,] }
immSEAS.acf <- acf(dataSEAS.ts,type="covariance",plot=FALSE)$acf
phi.nonseas <- immSEAS.acf[2,,] %*% solve(immSEAS.acf[1,,])
covmat <- immSEAS.acf[1,,] - phi.nonseas %*% immSEAS.acf[1,,] %*% t(phi.nonseas)
cov.gcd <- getGCD(covmat,N)
var.seas <- var.par2pre(array(phi.seas,c(N,N,1)))
var.nonseas <- var.par2pre(array(phi.nonseas,c(N,N,1)))
psi.init <- as.vector(c(cov.gcd[[1]][lower.tri(diag(N))],log(cov.gcd[[2]]),
              var.nonseas,var.seas))
# There are seven holiday regressors, so initialize these with zero
psi.init <- c(psi.init,matrix(rbind(colMeans(diff(data.ts[2:(T-1),])),
                                    matrix(0,nrow=7,ncol=N)),ncol=1))


# SARMA
mdl <- NULL
mdl <- sigex.add(mdl,seq(1,N),"sarma",c(1,1,1,0,52),NULL,"process",c(1,-1))
mdl <- sigex.meaninit(mdl,data.ts,0)


# model construction
mdl <- NULL
#mdl <- sigex.add(mdl,seq(1,N),"svarma",c(1,0,1,0,52),list(-1,1,1,1),"process",c(1,-1))
#mdl <- sigex.add(mdl,seq(1,N),"svarma",c(1,0,1,0,52),delta.vec,"process",c(1,-1))
mdl <- sigex.add(mdl,seq(1,N),"svarma",c(1,1,1,0,52),NULL,"process",c(1,-1))
mdl <- sigex.meaninit(mdl,data.ts,0)

for(i in 1:N) {
  mdl <- sigex.reg(mdl,i,ts(as.matrix(easter.reg[,i]),
                            start=start(easter.reg),
                            frequency=frequency(easter.reg),
                            names="Easter-day"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school1.reg[,i]),
                            start=start(school1.reg),
                            frequency=frequency(school1.reg),
                            names="School1-Start"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school1e.reg[,i]),
                            start=start(school1e.reg),
                            frequency=frequency(school1e.reg),
                            names="School1-End"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school2.reg[,i]),
                            start=start(school2.reg),
                            frequency=frequency(school2.reg),
                            names="School2-Start"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school2e.reg[,i]),
                            start=start(school2e.reg),
                            frequency=frequency(school2e.reg),
                            names="School2-End"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school3.reg[,i]),
                            start=start(school3.reg),
                            frequency=frequency(school3.reg),
                            names="School3-Start"))
  mdl <- sigex.reg(mdl,i,ts(as.matrix(school3e.reg[,i]),
                            start=start(school3e.reg),
                            frequency=frequency(school3e.reg),
                            names="School3-End"))
}


##################################
### PART IV: Model Fitting

constraint <- NULL
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(2,2,2,2,2,2,2),NULL))
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(3,3,3,3,3,3,3),NULL))
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(4,4,4,4,4,4,4),NULL))
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(5,5,5,5,5,5,5),NULL))
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(6,6,6,6,6,6,6),NULL))
constraint <- rbind(constraint,sigex.constrainreg(mdl,data.ts,list(7,7,7,7,7,7,7),NULL))

par.mle <- sigex.default(mdl,data.ts,constraint)
psi.mle <- sigex.par2psi(par.mle,mdl)

#psi.mle <- psi.init
par.mle <- sigex.psi2par(psi.mle,mdl,data.ts)

## run fitting: commented out, this took 2 weeks!
fit.mle <- sigex.mlefit(data.ts,par.mle,constraint,mdl,"bfgs",debug=TRUE)

## manage output
psi.mle <- sigex.eta2psi(fit.mle[[1]]$par,constraint)
hess <- fit.mle[[1]]$hessian
par.mle <- fit.mle[[2]]


## fit from first model
psi.mle <- c(0.51760596525827, 0.439939433340027, 0.341971516664744, 0.388139046943854,
             0.418853891103159, 0.464968608915972, 0.709312914960205, 0.455461460979668,
             0.339370325959773, 0.25187135366609, 0.230731337783255, 0.480592700293915,
             0.461178712098393, 0.420665953504732, 0.407603454396325, 0.654165574391287,
             0.616559331219179, 0.45821247032649, 0.559087776741675, 0.501500545560296,
             0.624756459479047, -4.11411535390305, -3.86649122997175, -4.12282006467438,
             -4.14352251305745, -4.09256331893617, -4.26412180312553, -3.99327709096135,
             0.287952470125721, 0.172856270613775, -0.0987415357712388, -0.0159501219190552,
             -0.0117633989684642, -0.208676716860187, -0.255056553429009,
             -0.351955505887804, -0.562379160585377, -0.0832526648219097,
             -0.29165087130511, -0.197545448522567, -0.117079402257721, -0.263093235048652,
             -0.438756004004964, 0.000173552147007219, -0.430479684549709,
             -0.232557419277058, -0.155434286705812, -0.157384299296414, 0.202163851374255,
             -0.100995838060292, -0.1406493949577, -0.22511938283935, -0.265783531343633,
             -0.277141800524594, -0.139489396762458, -0.272228846421287, -0.121442891487532,
             0.241157289412355, 0.288939373265785, 0.00841665529135235, -0.372240917121428,
             -0.00522765381325204, 0.152217530857665, -0.181638914000712,
             -0.104410527483493, -0.0172444190106532, 0.0591069966381966,
             -0.00784536156901487, -0.526539611649665, -0.160076911614434,
             -0.123449114302994, 0.310291324637662, 0.224040034000612, 0.126663777217909,
             0.0967704793221517, 0.314933553243371, -0.200354353866066, 0.720222711354317,
             0.479027318922281, 0.227016381822007, 0.228618821557728, 0.122634180604663,
             0.0675727153657555, 0.0937084330838046, 0.127918893211009, 0.358523578953586,
             0.301790107253761, 0.0158238445912163, 0.0248041997313273, -0.0182133219586081,
             -0.049060131106088, -0.0682389509773827, 0.0307700852545481,
             0.213632505971637, 0.248531585991733, 0.119521495830167, 0.0224399850959564,
             0.114381433699523, 0.00515092525609996, 0.0244106165476958, 0.0872444068550833,
             0.148064063633522, 0.23435894184544, 0.304008265942945, 0.0494482007392237,
             -0.0660320349267947, -0.0876846272573646, -0.146792651799283,
             -0.00596982919162906, 0.254908369648903, 0.211144277410917, 0.199819286316351,
             0.0446076493678591, -0.194584922380506, -0.106067215219364, -0.0900749669461375,
             -0.0957562999086835, -0.00717076071179665, 0.253412801452362,
             -0.0854624465656899, 0.11550020833978, 0.12647288394805, 0.170716918014375,
             0.114370397013362, 0.218874012579289, 0.190880751292308, 0.00215074003032701,
             -0.266297522612305, -0.137093567965138, 0.0851546535686134, -0.0149444051946342,
             0.0358090120843427, -7.65592755685606e-05, 0.0364386379329101,
             0.00169685678096456, -0.266297522612304, -0.137093567965138,
             0.0851546535686135, -0.0149444051946342, 0.0358090120843427,
             -7.6559275568536e-05, 0.15642984342176, 0.00070436907534173,
             -0.266297522612305, -0.137093567965139, 0.0851546535686135, -0.0149444051946342,
             0.0358090120843427, -7.65592755685972e-05, -0.172455161593865,
             -0.00233158509725544, -0.266297522612305, -0.137093567965138,
             0.0851546535686134, -0.0149444051946342, 0.0358090120843427,
             -7.65592755685624e-05, -0.0166107413493935, -0.00296386973878176,
             -0.266297522612305, -0.137093567965138, 0.0851546535686134, -0.0149444051946342,
             0.0358090120843427, -7.65592755685521e-05, 0.0976909319888783,
             -0.00559000446619553, -0.266297522612305, -0.137093567965138,
             0.0851546535686134, -0.0149444051946342, 0.0358090120843427,
             -7.6559275568555e-05, -0.0768525179813562, -0.00368827372534544,
             -0.266297522612305, -0.137093567965138, 0.0851546535686133, -0.0149444051946342,
             0.0358090120843427, -7.65592755685606e-05, 0.0489376995896597)


par.mle <- sigex.psi2par(psi.mle,mdl,data.ts)

## fit from 2nd model so far...
psi.mle <- c(0.405651271180959, 0.258124724536642, 0.285762646895448, 0.230739214919885,
            0.268141310246235, 0.285370974855944, 0.706639269163624, 0.44157071930402,
            0.31914888986124, 0.238205486340147, 0.213263605624242, 0.503122968222967,
            0.481541151569267, 0.421110120466148, 0.384016864767268, 0.688686932220649,
            0.590382860541528, 0.401561562080582, 0.565726488815163, 0.452675527411534,
            0.590474351831002, -3.77537995708688, -3.83800225591529, -4.13171791703996,
            -4.20485298504176, -4.12917468479442, -4.28242204383477, -4.0087900840661,
            1.26006163964584, 0.776509902243265, 0.286254011795089, -0.345739624185935,
            0.0169445510156986, -1.25594276816059, 0.33892556755348, 0.719652908774482,
            -0.0828886071263387, 0.360459770857838, 0.436681731960279, 0.342533653534436,
            -0.127586963414122, 0.294995766371958, 0.12120745993523, 1.91707982878947,
            -0.603245152481409, -0.425155518798637, 2.13958395162111, -0.443515305033537,
            0.152812198667894, -2.53260290186144, -1.20525790232059, -1.30835060387382,
            -3.19159006253348, -3.05408008647947, -2.75085413281999, -3.50475291389602,
            -0.880147911782251, 1.87491004772781, -1.42270762006879, -1.1139292505662,
            1.25159643461958, -0.114514053789042, -1.63704021500544, 2.68070908129257,
            1.42833727733312, -3.21815956680686, 2.4441930415146, -2.39519061315132,
            3.07253326657643, 0.188786658638007, -2.22694255472409, 0.516646412680514,
            2.2633376327303, 1.0998481369428, 2.82371494890256, 0.693302744207988,
            3.01968559747527, 0.798517072768356, 0.499763048599732, 0.32640857924848,
            0.220403165782498, 0.173116265161078, 0.189999427464269, 1.00004791795491,
            0.586805117344029, 0.436062885344307, 0.383145946157736, 0.119866241928474,
            0.974240784226599, 0.257031635164384, 0.418782832605927, 1.05791717012291,
            1.45991256557043, 1.52943157284092, 0.829400360551658, 1.10927457805188,
            0.93747529656277, 1.29917428033693, -0.335415282180844, -1.75842985149133,
            -3.03328656461204, -2.89500879172788, -2.95210200400251, -3.59318546585039,
            -2.3791322458768, -0.130818742016906, 0.116706041487112, -0.208607381239226,
            0.0474275832574307, 0.272733956458311, -0.296845295520931, -0.466038821577494,
            0.356096641409414, -0.0893955227430189, -0.611827560929734, 0.431624694289589,
            -0.0636081621830563, -0.213848381164287, 0.796140610092583, -0.481018823657795,
            -0.0785216746111002, -1.22833331735371, 0.879246308263166, 0.107247290931231,
            -0.252115670165398, -0.181015487555944, -0.00542163149213962,
            -0.290450979894108, -0.187206641803701, 0.119814974729978, -0.0417751559706289,
            0.0659416874274581, -0.0225893580707813, 0.103543336550228, -0.00205277839177083,
            -0.290450979894107, -0.187206641803701, 0.119814974729978, -0.0417751559706289,
            0.0659416874274582, -0.0225893580707812, 0.144411765904165, 0.00164670107727591,
            -0.290450979894108, -0.187206641803702, 0.119814974729978, -0.0417751559706289,
            0.0659416874274581, -0.0225893580707813, -0.186146298926655,
            0.0016082242236123, -0.290450979894108, -0.187206641803701, 0.119814974729978,
            -0.0417751559706289, 0.0659416874274581, -0.0225893580707813,
            -0.0581555898644954, 0.00366366076385317, -0.290450979894108,
            -0.187206641803701, 0.119814974729978, -0.0417751559706289, 0.0659416874274581,
            -0.0225893580707812, 0.0695223427702666, 0.00416565340703398,
            -0.290450979894108, -0.187206641803701, 0.119814974729978, -0.0417751559706289,
            0.0659416874274582, -0.0225893580707812, -0.0310015965387024,
            0.00476730544853283, -0.290450979894108, -0.187206641803701,
            0.119814974729978, -0.0417751559706289, 0.0659416874274581, -0.0225893580707813,
            0.0517800576812348)

##  model checking
resid.mle <- sigex.resid(psi.mle,mdl,data.ts)[[1]]
resid.mle <- sigex.load(t(Re(resid.mle)),start(data.ts),frequency(data.ts),colnames(data.ts),TRUE)
resid.acf <- acf(resid.mle,lag.max=2*53,plot=FALSE)$acf

#pdf(file="retResidAcf.pdf",height=10,width=10)
par(mfrow=c(N,N),mar=c(3,2,2,0)+0.1,cex.lab=.8,cex.axis=.5,bty="n")
for(j in 1:N)
{
  for(k in 1:N)
  {
    plot.ts(resid.acf[,j,k],ylab="",xlab="Lag",ylim=c(-1,1),cex=.5)
    abline(h=1.96/sqrt(T),lty=3)
    abline(h=-1.96/sqrt(T),lty=3)
  }
}
dev.off()

# HERE


## manage output
#psi.mle <- sigex.eta2psi(fit.mle[[1]]$par,constraint)
#hess <- fit.mle[[1]]$hessian
#par.mle <- fit.mle[[2]]












#################################
########################## METHOD 1: DIRECT MATRIX APPROACH ############
############################### SKIP ###############################

signal.trendann <- sigex.signal(data,param,mdl,1)
signal.seas.week1 <- sigex.signal(data,param,mdl,2)
signal.seas.week2 <- sigex.signal(data,param,mdl,3)
signal.seas.week3 <- sigex.signal(data,param,mdl,4)
signal.seas.week <- sigex.signal(data,param,mdl,c(2,3,4))
signal.sa <- sigex.signal(data,param,mdl,c(1,5))

extract.trendann <- sigex.extract(data,signal.trendann,mdl,param)
extract.seas.week1 <- sigex.extract(data,signal.seas.week1,mdl,param)
extract.seas.week2 <- sigex.extract(data,signal.seas.week2,mdl,param)
extract.seas.week3 <- sigex.extract(data,signal.seas.week3,mdl,param)
extract.seas.week <- sigex.extract(data,signal.seas.week,mdl,param)
extract.sa <- sigex.extract(data,signal.sa,mdl,param)

####################################################################
############################# METHOD 2: FORECASTING and WK SIGEX
############## RECOMMENDED METHOD #####################

#grid <- 70000	# high accuracy, close to method 1
#grid <- 700	# low accuracy, but pretty fast
grid <- 7000	# need grid > filter length
window <- 200
horizon <- 2000
#leads <- c(-rev(seq(0,window-1)),seq(1,T),seq(T+1,T+window))
#data.ext <- t(sigex.cast(psi,mdl,data,leads,TRUE))
target <- array(diag(N),c(N,N,1))

extract.trendann <- sigex.wkextract2(psi,mdl,data,1,target,grid,window,horizon,FALSE)
extract.seas.week <- sigex.wkextract2(psi,mdl,data,c(2,3,4),target,grid,window,horizon,FALSE)
extract.seas.week1 <- sigex.wkextract2(psi,mdl,data,2,target,grid,window,horizon,NULL,FALSE)
extract.seas.week2 <- sigex.wkextract2(psi,mdl,data,3,target,grid,window,horizon,NULL,FALSE)
extract.seas.week3 <- sigex.wkextract2(psi,mdl,data,4,target,grid,window,horizon,NULL,FALSE)
extract.sa <- sigex.wkextract2(psi,mdl,data,c(1,5),target,grid,window,horizon,NULL,FALSE)
extract.irr <- sigex.wkextract2(psi,mdl,data,5,target,grid,window,horizon,NULL,FALSE)


##################################################################
#################### LP splitting of trend and cycle #################

cutoff <- pi/365
trunc <- 50000	# appropriate for mu = pi/(365)

extract.trend <- sigex.lpfiltering(mdl,data,1,NULL,psi,cutoff,grid,window,trunc,TRUE)
extract.seas.ann <- sigex.lpfiltering(mdl,data,1,NULL,psi,cutoff,grid,window,trunc,FALSE)
extract.trendirreg <- sigex.lpfiltering(mdl,data,1,5,psi,cutoff,grid,window,trunc,TRUE)



#########################################
### get fixed effects

reg.trend <- NULL


################################# PLOTS

## time series Plots

trendcol <- "tomato"
cyccol <- "orchid"
seascol <- "seagreen"
sacol <- "navyblue"
fade <- 60

subseries <- 1

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,9),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,5,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,9),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,5,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


subseries <- 2

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,9),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,5,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,9),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,5,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


subseries <- 3

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,9),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,5,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,9),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,5,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


subseries <- 4

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,9),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,5,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,9),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,5,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


subseries <- 5

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,7),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,4,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,7),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,2,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


subseries <- 6

plot(data[,subseries],xlab="Year",ylab="",ylim=c(2,7),lwd=1)
#sigex.graph(extract.sa,reg.trend,begin,period,subseries,0,sacol)
sigex.graph(extract.trendirreg,reg.trend,begin,period,subseries,0,sacol,fade)
sigex.graph(extract.trend,reg.trend,begin,period,subseries,0,trendcol,10)
sigex.graph(extract.seas.ann,NULL,begin,period,subseries,4,seascol,10)
sigex.graph(extract.seas.week,NULL,begin,period,subseries,3,cyccol,fade)

plot(data[,subseries],xlab="Year",ylab="",ylim=c(0,7),lwd=1)
sigex.graph(extract.seas.week1,NULL,begin,period,subseries,3,cyccol,fade)
sigex.graph(extract.seas.week2,NULL,begin,period,subseries,2,cyccol,fade)
sigex.graph(extract.seas.week3,NULL,begin,period,subseries,1,cyccol,fade)


#################################
### Seasonality Diagnostics

sigex.seascheck(extract.trend[[1]],7,.04,1)
sigex.seascheck(extract.seas.ann[[1]],7,.04,1)
sigex.seascheck(extract.seas.week[[1]],7,.04,0)
sigex.seascheck(extract.trendirreg[[1]],7,.04,1)

sigex.seascheck(extract.trend[[1]],365,.04,1)
sigex.seascheck(extract.seas.ann[[1]],365,.04,1)
sigex.seascheck(extract.seas.week[[1]],365,.04,0)
sigex.seascheck(extract.trendirreg[[1]],365,.04,1)

###### Signal extraction diagnostics

round(sigex.signalcheck(extract.trendann[[1]][(horizon+1):(horizon+T),],param,mdl,1,100),digits=3)
round(sigex.signalcheck(extract.seas.week[[1]],param,mdl,c(2,3,4),100),digits=3)

### Spectral density plots

subseries <- 1

## spectral plots
week.freq <- 365/7
month.freq <- 365/(365/12)
ann.freq <- 1

spec.ar(ts(extract.trend[[1]][,subseries],frequency=period),main="")
abline(v=ann.freq,col=4)
abline(v=week.freq,col=2)
abline(v=2*week.freq,col=2)
abline(v=3*week.freq,col=2)
abline(v=month.freq,col=3)

spec.ar(ts(extract.sa[[1]][,subseries],frequency=period),main="")
abline(v=ann.freq,col=4)
abline(v=week.freq,col=2)
abline(v=2*week.freq,col=2)
abline(v=3*week.freq,col=2)
abline(v=month.freq,col=3)

spec.ar(ts(extract.seas.week1[[1]][,subseries],frequency=period))
abline(v=week.freq,col=2)

spec.ar(ts(extract.seas.week2[[1]][,subseries],frequency=period))
abline(v=2*week.freq,col=2)

spec.ar(ts(extract.seas.week3[[1]][,subseries],frequency=period))
abline(v=3*week.freq,col=2)

##################################
#	filter analysis

grid <- 700
frf.trendann <- sigex.getfrf(data,param,mdl,1,TRUE,grid)
frf.week1 <- sigex.getfrf(data,param,mdl,2,TRUE,grid)
frf.week2 <- sigex.getfrf(data,param,mdl,3,TRUE,grid)
frf.week3 <- sigex.getfrf(data,param,mdl,4,TRUE,grid)
frf.weeks <- sigex.getfrf(data,param,mdl,c(2,3,4),TRUE,grid)
frf.irr <- sigex.getfrf(data,param,mdl,5,TRUE,grid)
frf.sa <- sigex.getfrf(data,param,mdl,c(1,5),TRUE,grid)

len <- 500
wk.trendann <- sigex.getwk(data,param,mdl,1,TRUE,grid,len)
wk.week1 <- sigex.getwk(data,param,mdl,2,TRUE,grid,len)
wk.week2 <- sigex.getwk(data,param,mdl,3,TRUE,grid,len)
wk.week3 <- sigex.getwk(data,param,mdl,4,TRUE,grid,len)
wk.weeks <- sigex.getwk(data,param,mdl,c(2,3,4),TRUE,grid,len)
wk.irr <- sigex.getwk(data,param,mdl,6,TRUE,grid,len)







##### SCRAP
