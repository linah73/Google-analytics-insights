
library(tidyverse)
library(skimr)
library(openxlsx)
library(sjmisc)

# EXPLORATORY DATA ANALYSIS

#Load data
sessions_df <- read_csv("DataAnalyst_Ecom_data_sessionCounts.csv")
addsToCart <- read.csv("DataAnalyst_Ecom_data_addsToCart.csv")

#Inspect sessions data structure
str(sessions_df)

#Change variable names
#Change date column to date type, and browser amd deviceCategory columns to factor type
sessions_df <- sessions_df %>% 
  rename("Browser"="dim_browser", "Device"="dim_deviceCategory", "date"="dim_date") %>% 
  mutate(date = mdy(date)) %>%
  mutate(Browser=as.factor(Browser)) %>%
  mutate(Device=as.factor(Device)) 

#Quickly inspect Summary of data
sessions_df %>% summary()

#Inspect data for missing values and number of unique values per column
library(skimr)
sessions_df %>% skimr::skim()
#There are no empty values in the data set. Let's do a deep dive and check for masked missing values

#Inspect the unique values of the browser column
sessions_df %>% select(Browser) %>% unique()

#There is a value  "(not set)" which means google analytics couldn't retrieve this info
#There is also an "error" value. it is uncertain what type of errror occured
#Both these values indicate missing data

#Inspect how many sessions have missing values are in the data:
sessions_df %>% 
  filter(Browser %in% c("(not set)", "error") ) %>%
  group_by(Browser) %>% 
  summarise(total_sessions = sum(sessions)) %>% 
  mutate(prop = total_sessions/sum(sessions_df$sessions)*100)
#There are 117 "not set" sessions and 2359 "error" sessions. This is about 0.024% of the entire dataset
#The missing data is significantly small. There is no need to do any alterations at this point

##################################################################################

## PREPARE TABLES IN EXCEL WORKBOOK

#Month * Device aggregation of the data
per_month_device_sessions <- sessions_df %>%
  mutate(Month = floor_date(date, "month")) %>% #Set date to the beginning of the month
  group_by(Month, Device) %>% 
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>%
  mutate(ECR = Transactions/Sessions) %>%
  arrange(Month) 

#Change date format in table
per_month_device_sessions_table <- per_month_device_sessions %>% 
  mutate(Month = format(as.Date(Month), "%b %Y"))

library(openxlsx)

#Create workbook
wb <- createWorkbook()

decimal_style <- createStyle(numFmt = "0.00")
bold_style <- createStyle(textDecoration = "Bold", halign = "center", valign = "center")
percent_style <- createStyle(numFmt = "PERCENTAGE")

#Prepare excel sheet 1
addWorksheet(wb, "sheet1")
writeData(wb, sheet = "sheet1", x = "SESSION COUNTS BY MONTH AND DEVICE")
writeData(wb, sheet = "sheet1", x = per_month_device_sessions_table, startRow = 2, headerStyle = bold_style)
mergeCells(wb, sheet = "sheet1", cols = 1:6, rows = 1)

addStyle(wb, sheet = "sheet1", style = bold_style, rows = 1, cols = 1)
addStyle(wb, sheet = "sheet1", style = decimal_style, rows = 3:38, cols = 6)
addStyle(wb, sheet = "sheet1", style = percent_style, rows = 3:38, cols = 6)

saveWorkbook(wb, file="./webanalytics13.xlsx", overwrite = TRUE)


## Prepare worksheet 2


#Create month over month metrics table 2

#Aggregate sessions_df by  Month
per_month_sessions <- sessions_df %>%
  mutate(Month = floor_date(date, "month")) %>% #Set date to the beginning of the month
  group_by(Month) %>%
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>%
  mutate(ECR = Transactions/Sessions) 

#Add Year-Month column to addsToCart and merge with per_month_sessions.Calculate metrics
metrics <- addsToCart %>%
  mutate(Month = make_date(dim_year, dim_month)) %>% 
  inner_join(y = per_month_sessions, by = "Month") %>%
  arrange(Month) %>% 
  mutate(CCR = Transactions/addsToCart) %>%
  mutate(ACR = addsToCart/Sessions)


library(sjmisc)

#Create table for last two months
mom_metrics <- metrics %>%
  tail(2) %>%
  mutate(Month = format(as.Date(Month), "%b %Y")) %>% 
  select(Month, Sessions, addsToCart, Transactions, QTY, ECR, ACR, CCR) %>%
  rotate_df(cn = TRUE, rn="METRIC")%>% 
  mutate(Change = .[,3] - .[,2]) %>% 
  mutate(`Change %` = Change/.[,2])

#Add description of the metrics
mom_metrics[mom_metrics$METRIC == "ECR","Notes"] <- "ECR: eCommerce conversion rate"
mom_metrics[mom_metrics$METRIC == "ACR","Notes"] <- "ACR: Add to cart rate"
mom_metrics[mom_metrics$METRIC == "CCR","Notes"] <- "CCR: Cart conversion rate"


#Prepare excel sheet 2

addWorksheet(wb, "sheet2")
writeData(wb, sheet = "sheet2", x = "MONTH OVER MONTH COMPARISON")
writeData(wb, sheet = "sheet2", x = mom_metrics, startRow = 2, headerStyle = bold_style)
mergeCells(wb, sheet = "sheet2", cols = 1:6, rows = 1)


# Style color for conditional formatting
pos_style <- createStyle(fontColour = "#006100", bgFill = "#C6EFCE")
neg_style <- createStyle(fontColour = "#9C0006", bgFill = "#FFC7CE")

conditionalFormatting(wb, sheet = "sheet2",
                      cols = 5,
                      rows = 3:9, rule = ">= 0", style = pos_style) 
conditionalFormatting(wb, sheet = "sheet2",
                      cols = 5,
                      rows = 3:9, rule = "< 0", style = neg_style)


#styling
number_style <- createStyle(numFmt = "0")
decimal_style <- createStyle(numFmt = "0.00")
percent_style2 <- createStyle(numFmt = "0.00%")

addStyle(wb, sheet = "sheet2", style = bold_style, rows = 1, cols = 1)
addStyle(wb, sheet = "sheet2", style = decimal_style, rows = 3:9, cols = 5, gridExpand = T)
addStyle(wb, sheet = "sheet2", style = percent_style, rows = 3:9, cols = 5)
addStyle(wb, sheet = "sheet2", style = number_style, rows = 3:6, cols = 2:4, gridExpand = T)
addStyle(wb, sheet = "sheet2", style = percent_style2, rows = 7:9, cols = 2:4, gridExpand = T, stack=T)
addStyle(wb, sheet = "sheet2", style = bold_style, rows = 3:9, cols = 1)

#Save worksheet
saveWorkbook(wb, file="./webanalytics13.xlsx", overwrite = TRUE)


## Prepare Sheet 3 to store sessions per browser table and totals (additional tables)

#Create transactions per browser table of browsers with more than 5k total sessions
Browsers <- sessions_df %>%
  group_by(Browser) %>% 
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>%
  mutate(ECR = Transactions/Sessions) %>%
  mutate(`Sessions %` = 100 * Sessions / sum(Sessions)) %>% 
  mutate(`Transactions %` = 100 * Transactions / sum(Transactions)) %>% 
  mutate(`QTY %` = 100 * QTY / sum(QTY)) %>% 
  mutate_if(is.numeric, round, 3) %>%
  filter(Sessions > 5000) %>%
  arrange(desc(Sessions))
  

#Prepare sheet 3 table

decimal_style2 <- createStyle(numFmt = "0.00")

addWorksheet(wb, "sheet3")
writeData(wb, sheet = "sheet3", x = "SESSIONS PER BROWSER: TOP 10 BROWSERS")
writeData(wb, sheet = "sheet3", x = Browsers, startRow = 2, headerStyle = bold_style)
mergeCells(wb, sheet = "sheet3", cols = 1:8, rows = 1)
addStyle(wb, sheet = "sheet3", style = bold_style, rows = 1, cols = 1)
addStyle(wb, sheet = "sheet3", style = bold_style, rows = 3:12, cols = 1)
addStyle(wb, sheet = "sheet3", style = decimal_style2, rows = 3:12, cols = 5:8, gridExpand = T)
addStyle(wb, sheet = "sheet3", style = percent_style, rows = 3:12, cols = 5)
saveWorkbook(wb, file="./webanalytics13.xlsx", overwrite = TRUE)

# Prepare worksheet 4

#Prepare table of Totals 

#compute total 
addsToCart_total <- addsToCart %>% summarise(addsToCart = sum(addsToCart))
#Merge data
Totals <- sessions_df %>%
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>%
  cross_join(addsToCart_total) %>%
  mutate(ECR = Transactions/Sessions) %>%
  mutate(ACR = addsToCart/Sessions) %>%
  mutate(CCR = Transactions/addsToCart) %>%
  mutate_if(is.numeric, round, 3) %>% 
  select(Sessions, addsToCart, Transactions, QTY, ECR, ACR, CCR)

addWorksheet(wb, "sheet4")
writeData(wb, sheet = "sheet4", x = "TOTALS")
writeData(wb, sheet = "sheet4", x = Totals, startRow = 2, headerStyle = bold_style)
mergeCells(wb, sheet = "sheet4", cols = 1:7, rows = 1)
addStyle(wb, sheet = "sheet4", style = bold_style, rows = 1, cols = 1)
addStyle(wb, sheet = "sheet4", style = decimal_style2, rows = 3, cols = 5:7, gridExpand = T)
addStyle(wb, sheet = "sheet4", style = percent_style, rows = 3, cols = 5:7)
saveWorkbook(wb, file="./webanalytics13.xlsx", overwrite = TRUE)


################################################################################

# PLOTTING

library(ggplot2)


#Plot Conversion rate per device
per_month_device_sessions <- per_month_device_sessions %>% 
  mutate(ECR = 100 * ECR)  #Convert to percentage

per_month_device_sessions %>% 
  ggplot(aes(x=Month, y=ECR, group = Device, color= Device)) + 
           geom_point(size = 1.5, alpha = 0.5) +
           geom_line(linewidth = 1)+scale_color_manual(values=c( "#56B4E9","#4EADAF", "#88DEB0"))+
           geom_text(data=subset(per_month_device_sessions, Month == "2013-06-01"), 
                     aes(label = Device, color = Device, x = as.Date("2013-07-01"), 
                         y = ECR), hjust = .5, size=4) +
          scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
           theme_classic() +
           theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
                 axis.title.x = element_blank(),
                 panel.grid.major = element_blank(),
                 legend.position = "none",
                 aspect.ratio = 1/3)+
           labs( title = "Conversion rate per device", y="ECR (%)")



#Plot monthly sessions per device
per_month_device_sessions %>% 
  ggplot(aes(x=Month, y=Sessions, group = Device, color= Device)) + 
  geom_point(size = 1, alpha = 0.5) +
  geom_line(linewidth = 1)+
  scale_color_manual(values=c( "#56B4E9","#4EADAF", "#88DEB0"))+
  geom_text(data=subset(per_month_device_sessions, Month == "2013-06-01"), 
            aes(label = Device, color = Device, x = as.Date("2013-07-01"), 
                y = Sessions), hjust = .6, size=4) +
  theme_classic() +
  scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
        axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        legend.position = "none",
        aspect.ratio = 1/3)+
  labs( title = "Sessions per device")


#Plot total transactions per device

per_month_device_sessions %>% 
  ggplot(aes(x=Month, y=Transactions, group = Device, color= Device)) + 
  geom_point(size = 1.5, alpha = 0.5) +
  geom_line(linewidth = 1)+
  scale_color_manual(values=c( "#56B4E9","#4EADAF", "#88DEB0"))+
  geom_text(data=subset(per_month_device_sessions, Month == "2012-07-01"), 
            aes(label = Device, color = Device, x = as.Date("2012-05-01"), 
                y = Transactions),  hjust = -.1, size=4) +
  theme_classic() +
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  theme(axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        legend.position = "none",
        aspect.ratio = 1/3)+
  labs( title = "Transactions per device")


#Plot total sessions per device

#Pie chart: Compute the percentage proportions
pmd_sessions_prop <- per_month_device_sessions %>%
  group_by(Device)%>%
  summarise( propSessions = 100 * sum(Sessions) / sum(per_month_device_sessions$Sessions),
             propTransactions = 100 * sum(Transactions) / sum(per_month_device_sessions$Transactions), 
             propQTY = 100 * sum(QTY) / sum(per_month_device_sessions$QTY)) %>% 
  as.data.frame(.) %>% 
  mutate_if(is.numeric, round, 0)


#plot pie chart
ggplot(pmd_sessions_prop, aes(x = 1, y = propSessions, fill = Device)) +
  geom_col() +
  coord_polar(theta = "y") +
  geom_text(aes(label = paste( propSessions, "%")),
            position = position_stack(vjust = 0.5),
            size = 6) +
  theme_void(base_size = 15) +
  scale_fill_manual(values=c( "#56B4E9","#4EADAF", "#88DEB0"))+
  theme(plot.title = element_text(hjust = 0.5))+
  labs( title = "Total sessions per device", fill=NULL)


#plot pie chart
ggplot(pmd_sessions_prop, aes(x = 1, y = propTransactions, fill = Device)) +
  geom_col() +
  coord_polar(theta = "y") +
  geom_text(aes(label = paste( propTransactions, "%")),
            position = position_stack(vjust = 0.5),
            size = 6) +
  theme_void(base_size = 15)+
  scale_fill_manual(values=c( "#56B4E9","#4EADAF", "#88DEB0"))+
  theme(plot.title = element_text(hjust = 0.5))+
  labs( title = "Total transactions per device", fill=NULL)




##############################################################################


#Plot transactions per browser line chart for top 10
Browsers_monthly <- sessions_df %>%
  mutate(Month = floor_date(date, "month")) %>% #Set date to the beginning of the month
  group_by(Month, Browser) %>% 
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>% 
  arrange(Month) %>% 
  ungroup()  %>%
  mutate(ECR = 100 * Transactions/Sessions) %>%
  mutate(`Sessions %` = 100 * Sessions / sum(Sessions)) %>% 
  mutate(`Transactions %` = 100 * Transactions / sum(Transactions)) %>% 
  mutate(`QTY %` = 100 * QTY / sum(QTY)) %>% 
  mutate_if(is.numeric, round, 3) %>% 
  filter(Browser %in% Browsers$Browser[1:10])


#Plot monthly sessions per Browser top 10
Browsers_monthly %>% 
  filter(Browser %in% as.vector(Browsers$Browser[1:5])) %>%
  ggplot(aes(x=Month, y=Sessions, group = Browser, color= Browser)) + 
  geom_point(size = 1.5, alpha = 0.5) +
  geom_line(linewidth = 1)+
  theme_classic() +
  scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  scale_color_manual(values=c("darkgreen",  "#4EADAF", "#244A80", "#56B4E9", "#71b578"))+
geom_text(data=subset(Browsers_monthly, Month == "2013-06-01" & Browser %in% as.vector(Browsers$Browser[1:5])), 
          aes(label = c(paste("Chrome"),paste("Others"), paste(""),paste("Safari"),paste("")), color = Browser, x = as.Date("2013-08-01"), 
              y = Sessions), hjust = .8, size=3) +
  theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
        axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        aspect.ratio = 1/3,
        legend.position="bottom",
        legend.title = element_blank())+
  labs( title = "Sessions of top 5 browsers")



#Plot monthly transactions per Browser top 5

Browsers_monthly %>% 
  filter(Browser %in% as.vector(Browsers$Browser[1:5])) %>%
  ggplot(aes(x=Month, y=Transactions, group = Browser, color= Browser)) + 
  geom_point(size = 1.5, alpha = 0.5) +
  geom_line(linewidth = 1)+
  theme_classic() +
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
  scale_color_manual(values=c("darkgreen",  "#4EADAF", "#244A80", "#56B4E9", "#71b578"))+
  theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
        axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        aspect.ratio = 1/2,
        legend.position="none", 
        )+
  labs( title = "Transactions for top 5 browsers")



#Plot monthly ECR per Browser for top 5

Browsers_monthly %>% 
  filter(Browser %in% as.vector(Browsers$Browser[1:5])) %>%
  ggplot(aes(x=Month, y=ECR, group = Browser, color= Browser)) + 
  geom_point(size = 1.5, alpha = 0.5) +
  geom_line(linewidth = 1)+
  scale_color_manual(values=c("darkgreen",  "#4EADAF", "#244A80", "#56B4E9", "#71b578"))+
  scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
  geom_text(data=subset(Browsers_monthly, Month == "2013-06-01" & Browser %in% as.vector(Browsers$Browser[1:5])), 
            aes(label = Sessions, color = Browser, x = as.Date("2013-07-01"), 
                y = ECR), hjust = .4, size=3) +
  theme_classic() +
  theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
        axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        aspect.ratio = 1/2,
        legend.position = "top",
        legend.title = element_blank())+
  annotate(geom = "text", x = as.Date("2013-07-01"),
           y = 4.1, label = "Last month", size=3, fontface = "bold",  hjust = .6) +
  annotate(geom = "text", x = as.Date("2013-07-01"),
           y = 3.9, label = "sessions", size=3, fontface = "bold") +
  labs( title = "Conversion rates of top 5 browsers", y= "ECR (%)")


##############################################################################

#Compare Month over Month data for May and June

daily_metrics_may_june <- sessions_df %>%
  mutate(Year = format(as.Date(date), "%Y")) %>% 
  mutate(Month = format(as.Date(date), "%m")) %>% 
  mutate(Day = format(as.Date(date), "%d")) %>% 
  filter(Month %in% c("05", "06")) %>%
  group_by(Year, Month, Day) %>% 
  summarise(Sessions = sum(sessions),
            Transactions = sum(transactions),
            QTY = sum(QTY)) %>%
  mutate(date = make_date(Year, Month, Day)) %>%
  arrange(date)


#Plot May-June daily sessions and transactions
ggplot(daily_metrics_may_june) +
  geom_line(aes(x = date, y = Sessions, color=Month, group = 1), linewidth=1) +
  geom_line(aes(x = date, y = Transactions, color=Month, group = 1), linewidth=1)+
  scale_color_manual(values = c("05" = "#71b578", "06" = "#43b0f1"))+ 
  geom_vline(xintercept = as.Date("2013-06-01"), linetype="dashed", color="grey")+
  theme_classic() +
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  scale_x_date(date_breaks = "months" , date_labels = "%b %d")+
  theme(axis.title.x = element_blank(),
        panel.grid.major = element_blank(),
        legend.position = "none",
        aspect.ratio = 1/2)+
  annotate(geom = "text", x = as.Date("2013-05-02"),
           y = 30000, label = "Sessions", size=3, fontface = "bold") +
  annotate(geom = "text", x = as.Date("2013-05-03"),
           y = -2000, label = "Transactions", size=3, fontface = "bold") +
  annotate(geom = "text", x = as.Date("2013-06-01"),
           y = 120000, label = "Transactions", size=3, fontface = "bold") +
  annotate(geom = "text", x = as.Date("2013-05-28"),
           y = 110000, label = "28K", size=5, fontface = "bold", color="#71b578") +
  annotate(geom = "text", x = as.Date("2013-06-05"),
           y = 110000, label = "35K", size=5, fontface = "bold", color="#43b0f1") +
  annotate(geom = "text", x = as.Date("2013-06-01"),
           y = 145000, label = "Sessions", size=3, fontface = "bold")+
  annotate(geom = "text", x = as.Date("2013-05-28"),
  y = 135000, label = "1.16M", size=5, fontface = "bold", color="#71b578") +
  annotate(geom = "text", x = as.Date("2013-06-05"),
           y = 135000, label = "1.39M", size=5, fontface = "bold", color="#43b0f1") +
  labs( title = "Last 2 months sessions: May 2013 - June 2013")



#Plot month over month overlay sessions plot May - June
daily_metrics_may_june %>%
  mutate(Month = ifelse(Month == "05", "May", "June")) %>% 
  ggplot(aes(x=Day, y=Sessions, group = Month, color= Month)) + 
  geom_point(size = 1.5, alpha = 0.5) +
  scale_color_manual(values = c("May" = "#71b578", "June" = "#43b0f1"))+ 
  geom_line(linewidth = 1)+
  theme_classic() +
  scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
  theme(panel.grid.major = element_blank(),
        axis.title.x = element_blank(),
        axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
        legend.position='bottom',
        aspect.ratio = 1/2,
        legend.title = element_blank())+
  labs( title = "Daily sessions: May 2013 vs June 2013")


################################################################################


 #Plot sessions and adds to cart transactions
 metrics_long <-  metrics %>% 
   pivot_longer(c(Sessions, addsToCart, Transactions), names_to = "Metric", values_to = "Counts") 
 ggplot(data = metrics_long, aes(x = Month, y = Counts, fill = Metric, color=Metric), size = 1) + 
   geom_bar(stat = "identity", position ="identity") +
   scale_colour_manual(values=c("#43b0f1", "#43b0f1", "#43b0f1")) +
   scale_fill_manual(values=c( Sessions= "#43b0f1", Transactions="#00578a",addsToCart="#a8e6cf"))+
   theme_classic() +
   theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
         axis.title.x = element_blank(),
         axis.ticks.margin=unit(0,'cm'),
         panel.grid.major = element_blank(),
         panel.grid.minor = element_blank(),
         legend.position = "bottom")+
   scale_x_date(date_breaks = "months" , date_labels = "%b-%y", expand = c(0, 0))+
   scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3), expand = c(0, 0))+
   labs( title = "Session conversions",
         color=NULL, fill=NULL)
 

 #Plot overall sessions and transactions
 sessions_df %>%
   group_by(date) %>% 
   summarise(Sessions = sum(sessions),
             Transactions = sum(transactions),
             QTY = sum(QTY)) %>%
   ggplot(aes(x=date)) +
   geom_area(aes(y = Sessions), fill = "#43b0f1", 
             color = "#43b0f1", alpha=0.5) + 
  # geom_area(aes(y = Transactions), fill = "#00578a",
    #         color = "#00578a",  alpha=0.5, )  +
   theme_classic() +
   scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3))+
   theme(axis.title = element_blank(),
         axis.line.y = element_blank(),
         axis.line.x = element_blank(),
         panel.grid.major = element_blank(),
         axis.text.x=element_blank(),
         axis.ticks.x=element_blank(),
         axis.text.y=element_blank(),
         axis.ticks.y=element_blank())+
   labs( title = "")
 

 #Plot Adds-to-cart rate vs cart conversion rate July 2012 - June 2023
 

 #convert metrics to % 
 perc_metrics <- metrics %>% 
   mutate(ECR = 100 * ECR) %>%
   mutate(ACR = 100 * ACR) %>%
   mutate(CCR = 100 * CCR)
   
 ggplot(perc_metrics) +
   geom_line(aes(x = Month, y = Sessions),color = "blue",linetype="dotted") +
   geom_line(aes(x = Month, y = addsToCart),color = "blue", linetype="dotted") +
   geom_line(aes(x = Month, y = 100000*CCR), linewidth = 1, color="#00578a", group = 1) +
   geom_line(aes(x = Month, y = 100000*ACR), linewidth = 1, color="#43b0f1", group = 1) +
   scale_y_continuous(labels = scales::unit_format(unit = "K", scale = 1e-3), name = "Counts",
                      sec.axis = sec_axis(~./100000, name = "Rate %")) +
   scale_x_date(date_breaks = "months" , date_labels = "%b %Y")+
   theme_classic() +
   theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust=1),
         axis.title.x = element_blank(),
         panel.grid.major = element_blank(),
         aspect.ratio = 1/2) +
   annotate(geom = "text", x = as.Date("2012-06-01"),
            y = 2500000, label = "ACR", fontface = "bold", color = "#43b0f1") +
   annotate(geom = "text", x = as.Date("2012-06-01"),
            y = 1000000, label = "CCR", fontface = "bold", color = "#00578a") +
   annotate(geom = "text", x = as.Date("2012-06-01"),
            y = 800000, label = "Sessions", fontface = "bold", color = "blue", size=3) +
   annotate(geom = "text", x = as.Date("2012-05-01"),
            y = 200000, label = "addsToCart", fontface = "bold", color = "blue", size=3,  hjust = -.1) +
   labs( title = "Change in cart activity over the year")

 

   