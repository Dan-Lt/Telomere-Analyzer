library(BiocManager)
library('BSgenome')
library('stringr')
library(tidyverse)  
library(IRanges)
library(purrr)
# library(data.table)
library("parallel")


split_telo <- function(dna_seq, sub_length = 100){
  #' @title Splits a DNA sequence nto subsequences. 
  #' @description This function calculate the sequence ength and creates IRanges objects of subseuences of a given length
  #' if The dna_seq%%subseq != 0   and last' width < sub_length/2 Then we will remove this last index making the last subtelomere longer then by. (because we want to prevent a case where we have for 
  #' example subtelomere of length < sub_length/2 which is too short to consider -> then the last subtelomere is a bit longer)
  #' If the length of dna_seq is less then the sub_length it will return an empty Iranges Object.            
  #' @usage 
  #' @param dna_seq: DNAString object 
  #' @param sub_length: The length of each subsequence
  #' @value An IRanges object of the subsequences.
  #' @return iranges_idx: IRanges obsject of the indices of each subsequence
  #' @examples 
  idx_start <- seq(1,length(dna_seq), by=sub_length)
  idx_end <- idx_start + sub_length -1
  idx_end[length(idx_end)] <- length(dna_seq)
  if(length(dna_seq) - last(idx_start) < (sub_length/2)){ # if last subsequence is less then 50% 
    idx_start <- idx_start[1:length(idx_start)-1]
    idx_end <- idx_end[1:length(idx_end)-1]
    idx_end[length(idx_end)] <- length(dna_seq)
  }
  idx_ranges <- IRanges(start = idx_start, end = idx_end)
  return(idx_ranges)
} # IRanges object



# my improvment: fiding the IRanges and making union for overlaps and then calculate according to sum(width of the IRanges)
# The calculation is on the full sequence and it is not fit for subsequences
get_densityIRanges <- function(sequence, patterns){
  #' @title Pattern searching function.
  #' @description: get the density of a given pattern or a total density of a list of patterns, and IRanges of the patterns.
  #' @param pattern: a list of patterns or a string of 1 pattern.
  #' @param sequence: DNAString object
  #' @value A numeric for the total density of the pattern(patterns) in the sequences, a IRanges object of the indcies of the patterns found.
  #' @return a tuple of (density, IRanges) Total density of all the patterns in the list( % of the patterns in this sequence) and the IRanges of them
  #' @examples 
  total_density <- 0 
  mp_all <- IRanges()# union of all the IRanges of all the patterns in the list 
  if(is.list(patterns)){
    patterns <- unique(patterns)  # make sure there are no dups
    for( pat in patterns){
      mp_all <- union.Vector(mp_all, matchPattern(pattern = pat, subject = unlist(sequence), max.mismatch = 0) )
    }
  }
  else{
    mp_all <- matchPattern(pattern = patterns, subject = unlist(sequence), max.mismatch = 0)
    mp_all <- union.Vector(mp_all, mp_all) # incase there are overlaps
  }
  total_density <-sum(width(mp_all)) / nchar(sequence)
  return(list(total_density, mp_all))
}  


get_sub_density <- function(sub_irange, ranges){
  #' @title Calculate density of a subsequnce.
  #' @details with a given IRanges of a subsequence and IRanges of patterns, compute the density of the IRanges within the 
  #'        subseuence range.
  #' @param sub_irange: the IRange of the subsequence
  #' @param ranges: The IRanges of the patterns found in the full sequence
  #' @value a numeric which is the density in range [0,1].  
  #' @return The density of the patterns in the subseuence according to the IRanges.
  #' @description  sub_irange = (10, 30), ranges = {(2,8), (16,21), (29,56)} -> the intersect is {(16,21), (29, 30)} -> 
  #                width = 6+2 = 8 , sub_irange width = 21 -> density = 8/21
  #' @examples sub_irange <- IRanges(start = 10, end = 30)
  #'           ranges <- IRanges(start = c(2,16,29), end = c(8,21,56))
  #'           get_sub_density(sub_irange =  sub_irange, ranges = ranges) # 0.3809524
  # this compute the desity of iranges of patterns within a given irange of a subsequence
  return( sum(width( intersect.Vector(sub_irange, ranges))) / width(sub_irange) ) 
}


###########3 My cahnge from prev - return a list 0f (df, total_density) ###############
analyze_subtelos <- function(dna_seq, patterns , sub_length = 100, MIN_DENSITY = 0.18){ # return list(subtelos, list_density_mp[1])
  #' @title Analyze the patterns for each subsequence.
  #' @description s split a dna sequence to subsequences and calculate the density of each subsequence
  #' @param dna_seq: a dna sequence (DNAString object)
  #' @param patterns: a list of patterns or a string of 1 pattern
  #' @param sub_length: The length of the subsequences for split_telo fuction.s
  #' @value a list(data frame of all subtelomeres and their properties ,numeric for total density)
  #' @return  a list of (a data frame, list(numeric: total density, IRanges for patterns) 
  #' @examples 
  
  
  # aother option is to create 5 vector s and then make a data.table from them
  
  # density and iranges of matchPattern
  list_density_mp <-get_densityIRanges(dna_seq, patterns = patterns)
  #density <- list_density_mp[[1]]
  mp_iranges <- list_density_mp[[2]]
  # get start indexes of "subtelo"
  idx_iranges <- split_telo(dna_seq, sub_length = sub_length) 
  # create empty dataframe which will contain all subtelomeres and their properties
  subtelos <- data.frame(ID = as.integer(), start_index = as.integer(), end_index = as.integer(), density = as.numeric(), class = as.numeric() )
  cur.ID <- 1             # intitialize ID counter
  # loop through start indexs
  for(i in 1:length(idx_iranges)){
    #first.idx <- start(idxs_iranges[i])
    #last.idx <- end(idxs_iranges)
    subtelo.density <-get_sub_density(sub_irange= idx_iranges[i] , ranges = mp_iranges)
    #cur.seq <- subseq(dna_seq, start = first.idx, end = last.idx )  #instead_of  substr(dna.seq, first.idx, last.idx)         # sequence of the current subtelomere
    # subtelo.density <- get_density(cur.seq, patterns = patterns)        # calculate all density and classify each subtelo for the patern "CCCTRR"
    CLASSES <- list('CCCTAA'=-5, 'NONE'=1, 'SKIP'=0)
    
    
    ###############3 NEED TO CHANGE FOR AN ARGUMENT OF CLASSES #####################
    subtelo.class <- CLASSES$CCCTAA
    if(subtelo.density < MIN_DENSITY){
      if(subtelo.density < 0.1){
        subtelo.class <- CLASSES$SKIP
      }
      else{
        subtelo.class <- CLASSES$NONE
      }
    }
    #subtelos <- rbindlist(list(subtelos, list(cur.ID, start(idx_iranges[i]) , end(idx_iranges[i]), subtelo.density, subtelo.class)))
    subtelos <- subtelos %>%
      add_row(ID = cur.ID, start_index =start(idx_iranges[i]) , end_index = end(idx_iranges[i]), density = subtelo.density, class = subtelo.class)
    cur.id <- cur.ID + 1
  }
  return( list(subtelos, list_density_mp) ) # return the subtelos df and the list(total density, mp_iranges)
}
#  a a list of (a data frame, numeric: total density) 


# I need to put The CLASSES as an arument ?
find_telo_position <- function(seq_length, subtelos, min_in_a_row = 3, min_density_score = 2){ # 15,10 for sub_length == 20 
  #' @title: Find the position of the Telomere(subsequence) within the seuence.
  #' @description:  Find the start and end indices of the subsequence within the sequence according to a data frame.
  #' @usage 
  #' @param seq_length: The length of the read.
  #' @param subtelos: data frame of a subseuences indices, density and class (from the analyze_subtelos)
  #' @value An IRanges object of length 1.
  #' @return (start, end) irange  of the Telomere.
  #' @examples
  
  ###############3 NEED TO CHANGE FOR AN ARGUMENT OF CLASSES #####################
  CLASSES <- list('CCCTAA'=-5, 'NONE'=1, 'SKIP'=0)  # # we have a problem in this function: Error in if (subt$class == CLASSES$SKIP | subt$class == CLASSES$NONE |  : argument is of length zero
  # set score, start, in.a.row to 0,-1,0
  
  score <- 0.0
  start <- -1
  end <- -1
  in_a_row <- 0
  start_end_diff <- subtelos[1, "end_index"] - subtelos[1, "start_index"] 
  
  # loop through subsequences
  end_position <- 0 # for end loop
  for (i in 1:nrow(subtelos)){ # CLASSES <- list('CCCTAA'=-5, 'NONE'=1, 'SKIP'=0)
    subt <- subtelos[i,]
    # if the subsequence's class is SKIP, NONE or NA, reset values
    if (subt$class == CLASSES$SKIP | subt$class == CLASSES$NONE | is.na(subt$class)){
      score <- 0
      start <- -1
      in_a_row <- 0
    }
    else{
      # otherwise add one to in.a.row, update score and set start index
      in_a_row <- in_a_row + 1
      score <- score + subt$density
      if (start == -1){
        start <- subt$start_index
      }
    }
    # if more than MIN.IN.A.ROW subtelomeres were found and the overall score is high enough, return start index
    if(in_a_row >= min_in_a_row && score >= min_density_score){
      j <- i+1
      end_position <- i+1
      break
    }
  }
  if(end_position == 0){
    return(IRanges(1,1)) # no telomere was found 
  }
  
  
  
  # search for end from the last subsequence (backward to finding stat incase there is island of non-telomeric subsequence)
  end <- -1 
  score <- 0.0
  in_a_row <- 0
  for (i in nrow(subtelos):end_position){ # CLASSES <- list('CCCTAA'=-5, 'NONE'=1, 'SKIP'=0)
    subt <- subtelos[i,]
    # if the subsequence's class is SKIP, NONE or NA, reset values
    if (subt$class == CLASSES$SKIP || subt$class == CLASSES$NONE || is.na(subt$class) ){
      score <- 0.0
      end <- -1
      in_a_row <- 0
    }
    else{
      # otherwise add one to in.a.row, update score and set start index
      in_a_row <- in_a_row + 1
      score <- score + subt$density
      if (end == -1){
        end <- subt$end_index
      }
    }
    # if more than MIN.IN.A.ROW subtelomeres were found and the overall score is high enough, return start index
    if(in_a_row >= min_in_a_row && score >= min_density_score){
      break
    }
  }
  
  
  
  if( start > end){
    end <- start + start_end_diff
    #browser()  ###### https://support.rstudio.com/hc/en-us/articles/205612627-Debugging-with-the-RStudio-IDE
  }
  
  return(IRanges(start = start, end = end))
}

# check the plot
# I need to adjust the plot to my code
# dna.seq is a DNAStringSet of length 1
# This is version updated at 6.01.2022
plot_single_telo <- function(x_length, seq_length, subs, serial_num, seq_start, seq_end,save.it=T, main_title = "", w=750, h=300, OUTPUT_JPEGS){ # add OUTPUT_JPEGS as arg
  #' @title plot the density over a sequence
  #' @param x_length: The length of the x axis.
  #' @param seq_length: The length of the sequence
  #' @param subs: the data frame of subseuences from the analyze_subtelos function
  #' @param serial_num: The serial number of the current sequence, used as the name of the file
  #' @param seq_start: The start of the Telomere.
  #' @param seq_end: The end " ".
  #' @param sava.it: save the file if TRE
  #' @param main_title: ad a title.
  #' @param w: width of the jpeg
  #' @param h: height of the jpeg
  #' @param OUTPUT_JPEGS: the output directory for saving the file
  subs <- na.omit(subs)
  # save file if specified
  if(save.it){
    jpeg_path <- paste(OUTPUT_JPEGS, paste('read', serial_num, '.jpeg',sep=''), sep='/')  
    jpeg(filename=jpeg_path, width=w, height=h)                                                            
  }
  
  
  # 26-07: my addition: save the csv file subs
  # write_csv(x = subs, file = paste(OUTPUT_JPEGS, paste('read', serial_num, '.csv',sep=''), sep='/') )
  
  
  # give extra x for the legend at the topRigth
  plot(subs$density ~ subs$start_index, type='n', yaxt='n', xaxt='n',ylab='', xlab='', ylim=c(0,1), xlim=c(1,x_length + round(x_length/4.15)) ) 
  # create axes
  xpos <- seq(1, x_length, by=1000) # I have cahnged from 0 to 1
  axis(1, at=xpos, labels=sprintf("%.1fkb", xpos/1000)); title(xlab = "Position", adj = 0)
  axis(2, at=seq(-0.1,1,by=0.1), las=2)
  # add polygon to plot for each variant repeat. 
  # mychange: only comp_ttaggg 
  polygon(y=c(0,subs$density,0), x=c(1,subs$start_index,seq_length), col=rgb(1,0,0,0.5), lwd=0.5) # change c(1,) instead of c(0, ) for x
  
  rect(xleft = seq_start, ybottom = -0.1, xright = seq_end, ytop = 0, col = "red") # 
  rect(xleft = seq_end+1, ybottom = -0.1, xright = seq_length, ytop = 0, col = "blue")
  if(seq_start > 1){
    rect(xleft = 1, ybottom = -0.1, xright = seq_start, ytop = 0, col = "blue")
  }
  
  abline(h=1, col="black", lty = 2)
  abline(h=0, col="black", lty = 2)
  legend(x = x_length, y = 1, legend=c("telomere", "sub-telomere"),col=c("red", "blue"), lty=1, lwd= 2,cex=1.2)
  sub_title <- paste("read length:", seq_length, ", telomere length:", abs(seq_start-seq_end)+1)
  title( main = main_title, sub = sub_title, ylab='Density')
  dev.off()
  
}



# has bug, more accurate then the default of getting the density of subsequence , because it can calculate the edges which has the partial of the pattern
filter_first_100 <- function(sequence, patterns, min_density = 0.18, start = 1,end = 100){
  #' Title: filter only sequences which thier subseq has at least minimal density of the given patterns
  #' have density of at least min_density
  #' 
  #' Notice that it is not accurate since it is nly a subsequnce, does not count patterns which are at the edges ( starts before start or ends after end )
  #' 
  #' @param sequence: a dna sequence (DNAString object)
  #' @param pattern: a list of patterns or a string of 1 pattern
  #' @param min_density: threshold for the density of the pattern
  #' @param start: the start index of the subsequnce
  #' @param end: the end "      "     
  #' @return a list of (logical, numeric), the logical indicates if the density of the subsequnce is >= min_density, and the numeric
  end_2 <- end+100 # take a subseuence which is large enough for not missing patterns at the edges
  ranges <- IRanges(start = start, end = end)
  sub_ranges <- get_densityIRanges(sequence = unlist(subseq(sequence,start = 1, end = end2)), patterns = patterns)[2] # return(list(total_density, mp_all))
  densities <- get_sub_density(sub_irange = sub_ranges, ranges = ranges)
  if(densities >= min_density){
    return(list(TRUE, densities))
  }
  else{
    return(list(FALSE, densities))
  }
}






############## Running functions #############################################################  


# removed the telorrete
# removed the if condition(filter), all sequences input are already came passing the filter 
# added a serial_start _ to work with:
searchPatterns <- function(sample_telomeres , pattern_list, max_length = 1e5, csv_name = "summary",output_dir,serial_start = 1, min_density,  title = "Telomeric repeat density"){
  #'@title Search given Patterns over a DNA sequences.
  #'@param sample_telomeres: the DNAString Set of the reads.
  #'@param pattern_list: a list of patterns or a string of 1 pattern.
  #'@param max_length: The x-axis length for the plot.
  #'@param csv_name: The name of the csv file
  #'@param output_dir: 
  #'@param serial_start: The first id serial number.
  #'@param min_density: The minimal density of the patterns in a sequence to be consider relevant.
  #'@param title: The title for the density plots.
  
  if(!dir.exists(output_dir)){ # update  did it 
    dir.create(output_dir)
  }
  
  OUTPUT_TELO_CSV <- paste(output_dir, paste(csv_name, 'csv', sep='.'), sep='/')
  OUTPUT_TELO_FASTA <- paste(output_dir, paste("reads", 'fasta', sep='.'), sep='/')
  OUTPUT_JPEGS <- paste(output_dir, 'single_read_plots', sep='/')
  dir.create(OUTPUT_JPEGS)
  OUTPUT_JPEGS.1 <- paste(output_dir, 'single_read_plots_adj', sep='/')
  dir.create(OUTPUT_JPEGS.1)
  
  #max_length <- max(width(sample_telomeres))
  #  I HAVE ADDED TLOMERE LENGTH, START @ END
  df<-data.frame(Serial = integer(), sequence_ID = character(), sequence_length = integer(), telo_density = double()
                 , Telomere_start = integer(), Telomere_end = integer(), Telomere_length = integer())
  # add telo density : get_sub_density <- function(sub_irange, ranges){
  LargeDNAStringSet <- DNAStringSet() # For the fasta output of the reads which pass the filter
  current_serial <- serial_start
  
  for( i in 1:length(sample_telomeres) ){
    current_fastq_name <- names(sample_telomeres[i])
    current_seq <- unlist(sample_telomeres[i])
    # we skip the adaptor and telorete so we start with base 57
    
    
    #################### NEED TO MAKE IT MORE RUBUST , MAYBE ADD THE FILTER FUNCTION AS AN INPUT ########################
    #current_filt_100 <-  get_densityIRanges( subseq(current_seq, start = length(current_seq)-99, end = length(current_seq) ), patterns = pattern_list) 
    
    # # returns a a list of (a data frame, list(numeric: total density,iranges)) 
    analyze_list <- analyze_subtelos(dna_seq = current_seq , patterns =  pattern_list, MIN_DENSITY = min_density)
    telo_irange <- find_telo_position(seq_length = length(current_seq), subtelos = analyze_list[[1]], min_in_a_row = 10, min_density_score = 6 )
    
    
    irange_telo <- analyze_list[[2]][[2]]
    if(width(telo_irange) < 100 ) {next} # not considered a Telomere
    s_index <- start(telo_irange) 
    # make the strat/end more accurate (usethe IRanges for the patterns)
    iranges_start <- which(start(irange_telo) %in% s_index:(s_index + 100)) 
    if(length(iranges_start) > 0){ start(telo_irange) <- start(irange_telo[iranges_start[1]])} 
    # try more accurate: take the max of which and also check new_end >= new_start before updating the IRange object
    e_index <- end(telo_irange) 
    iranges_end <- which(end(irange_telo) %in% (e_index - 100):e_index)
    if(length(iranges_end) >0 ) {
      #end(telo_irange) <- end(irange_telo[iranges_end[1]])} 
      new_end <- end(irange_telo[iranges_end[length(iranges_end)]])# take the last pattern in range 
      if(new_end >= start(telo_irange)){  end(telo_irange) <- new_end} # make sure end >= start     
    }  
    
    # Onc ew have the Telomere indices calculate the density of the patterns within it's range.
    telo_density <- get_sub_density(telo_irange, analyze_list[[2]][[2]])
    
    df <- df %>%
      add_row(Serial = current_serial, sequence_ID = current_fastq_name, sequence_length = length(current_seq), 
              telo_density = telo_density, Telomere_start = start(telo_irange), Telomere_end = end(telo_irange), Telomere_length = width(telo_irange))
    
    if(max_length < length(current_seq)){
      max_length <- current_seq
    }
    
    plot_single_telo(x_length =max(max_length, length(current_seq)), seq_length = length(current_seq), subs =  analyze_list[[1]], serial_num = current_serial ,
                     seq_start = start(telo_irange),seq_end = end(telo_irange), save.it=T, main_title = title,  w=750, h=300, OUTPUT_JPEGS= OUTPUT_JPEGS)
    plot_single_telo(x_length = length(current_seq), seq_length = length(current_seq), subs =  analyze_list[[1]], serial_num = current_serial ,
                     seq_start = start(telo_irange),seq_end = end(telo_irange), save.it=T, main_title = title,  w=750, h=300, OUTPUT_JPEGS= OUTPUT_JPEGS.1)
    
    LargeDNAStringSet <- append(LargeDNAStringSet, values = sample_telomeres[i])
    current_serial <- current_serial + 1
    
    
  } # end of for loop
  
  # need to save the df in a file
  write.csv(x=df, file=OUTPUT_TELO_CSV)
  writeXStringSet(LargeDNAStringSet, OUTPUT_TELO_FASTA)
  message("Done!") #  now what's left is to extract the sequences from fasta to fasta using the read_names list file ( 3 files )
  
} # end of the function searchPatterns



Find_Telorette <- function(read_subseq, telorette_pattern)
{
  for(i in 0:15){
    current_telorete <- matchPattern(pattern = telorette_pattern, subject = read_subseq, max.mismatch = i, with.indels = T)
    if(length(current_telorete) > 0) { break}
  }
  return(current_telorete)
}



searchPatterns_withTelorette <- function(sample_telomeres , pattern_list, max_length = 1e5, csv_name = "summary",output_dir, serial_start = 1, min_density, telorete_pattern, title = "Telomeric repeat density"){
  #'@title Search given Patterns over a DNA sequences.
  #'
  #'
  #'@param sample_telomeres: the DNAString Set of the reads.
  #'@param pattern_list: a list of patterns or a string of 1 pattern.
  #'@param csv_name: The name of the csv file
  #'@param output_dir: 
  #'@param min_density: The minimal density of the patterns in a sequence to be consider relevant.
  #'@param telorete_pattern: The patern of the telorete
  #'@param title: The title for the density plots.
  #'
  
  
  if(!dir.exists(output_dir)){ # update  did it 
    dir.create(output_dir)
  }
  
  
  OUTPUT_TELO_CSV <- paste(output_dir, paste(csv_name, 'csv', sep='.'), sep='/')
  OUTPUT_TELO_FASTA <- paste(output_dir, paste("reads", 'fasta', sep='.'), sep='/')
  OUTPUT_JPEGS <- paste(output_dir, 'single_read_plots', sep='/')
  dir.create(OUTPUT_JPEGS)
  OUTPUT_JPEGS.1 <- paste(output_dir, 'single_read_plots_adj', sep='/')
  dir.create(OUTPUT_JPEGS.1)
  
  #max_length <- max(width(sample_telomeres))
  
  
  #  I HAVE ADDED TLOMERE LENGTH, START @ END
  df<-data.frame(Serial = integer(), sequence_ID = character(), sequence_length = integer(),  telo_density = double(),
                 Telorette3 = logical(), Telorette3Start_index = integer(), Telorette_seq = character(), Telomere_start = integer(), Telomere_end = integer(), Telomere_length = integer())
  
  
  # add telo density : get_sub_density <- function(sub_irange, ranges){
  LargeDNAStringSet <- DNAStringSet() # For the fasta output of the reads which pass the filter
  current_serial <- serial_start
  
  for( i in 1:length(sample_telomeres) ){
    current_fastq_name <- names(sample_telomeres[i])
    current_seq <- unlist(sample_telomeres[i])
    # we skip the adaptor and telorete so we start with base 57
    
    
    # # returns a a list of (a data frame, list(numeric: total density,iranges)) 
    analyze_list <- analyze_subtelos(dna_seq = current_seq , patterns =  pattern_list, MIN_DENSITY = min_density)
    
    #list_CurrentDens_MP <- get_densityIRanges(current_seq, patterns = PATTERNS_LIST) # to remove: last_100_density = double(), total_density = double(),
    #current_telorete <- matchPattern(pattern = telorete_pattern, 
    #                                 subject = subseq(current_seq, start =length(current_seq) -86, end = length(current_seq)), max.mismatch = 14, with.indels = TRUE)
    
    current_telorete <- Find_Telorette(read_subseq = subseq(current_seq, start =length(current_seq) -86, end = length(current_seq)) , telorette_pattern = telorete_pattern)
    
    
    telo_irange <- find_telo_position(seq_length = length(current_seq), subtelos = analyze_list[[1]], min_in_a_row = 10, min_density_score = 6)
    
    irange_telo <- analyze_list[[2]][[2]]
    if(width(telo_irange) < 100 ) {next} # not considered a Telomere
    s_index <- start(telo_irange) 
    # make the strat/end more accurate (usethe IRanges for the patterns)
    iranges_start <- which(start(irange_telo) %in% s_index:(s_index + 100))  # change to 20 if subseq == 20
    if(length(iranges_start) > 0){ start(telo_irange) <- start(irange_telo[iranges_start[1]])} 
    
    e_index <- end(telo_irange) 
    iranges_end <- which(end(irange_telo) %in% (e_index - 100):e_index)
    if(length(iranges_end) >0 ) {
      #end(telo_irange) <- end(irange_telo[iranges_end[1]])} 
      new_end <- end(irange_telo[iranges_end[length(iranges_end)]])# take the last pattern in range 
      if(new_end >= start(telo_irange)){  end(telo_irange) <- new_end} # make sure end >= start 
    }
    
    
    
    
    if(length(current_telorete)){ # The telorrete was found
      telo_density <- get_sub_density(telo_irange, analyze_list[[2]][[2]])
      " check if the telomre starts after the tellorete.. for meanwhile don't do it....
        # check if the telomre starts after the tellorete
        if( start(telo_irange) <= end(current_telorete[[1]]) ){ # check if the telorrete is before the start of the Telomere
          new_start <- end(current_telorete[[1]]) + 1
          if(end(telo_irange) <= new_start) { # The tellorete was found after the telomere
            
            ##################### CHECH IN THE FUTURE ###################
            if( width(telo_irange) < 200 ) {next}# won't be considered Telomere, COULD BE PROBLEMATIC IF WE HAVE TO SUBSEQUENCES WHICH CAN BE TELOMERES
            # else we leave it to be before the telorette
          }
          else{ # update the start of the Telo after the telorrete 
            telo_irange <- IRanges(start = new_start, end = end(telo_irange))
          }
        }
        "              # to remove: last_100_density = double(), total_density = double(),
      df <- df %>% add_row(Serial = current_serial, sequence_ID = current_fastq_name, sequence_length = length(current_seq), telo_density = telo_density,
                           Telorette3 = TRUE, Telorette3Start_index = start(current_telorete[1]) + length(current_seq) -87,
                           Telorette_seq = toString(unlist((current_telorete[1]))), Telomere_start = start(telo_irange), Telomere_end = end(telo_irange), Telomere_length = width(telo_irange))  
    }
    else{ # no telorrete
      df <- df %>% add_row(Serial = current_serial, sequence_ID = current_fastq_name, sequence_length = length(current_seq),telo_density = telo_density,Telorette3 = FALSE,
                           Telorette3Start_index = -1 , Telorette_seq = "",Telomere_start = start(telo_irange), Telomere_end = end(telo_irange), Telomere_length = width(telo_irange))  
    }
    # now save a plot 
    # plot_single_telo <- function(seq_length, subs, serial_num ,save.it=T, legend_string = c("TTAGGG density"),  w=500, h=200, OUTPUT_JPEGS)
    # need to add the start, end positions
    
    # plot_single_telo(seq_length, subs, serial_num, telo_irange,save.it=T, main_title = "", w=500, h=200, OUTPUT_JPEGS){ # add OUTPUT_JPEGS as arg
    # THE PLOT WITH AN ADJUST  X-AXIS LENGTH ACCORDING TO THE READ LENGTH
    
    plot_single_telo(x_length = length(current_seq),seq_length = length(current_seq), subs =  analyze_list[[1]], serial_num = current_serial,
                     seq_start = start(telo_irange),seq_end = end(telo_irange), save.it=T, main_title = title,  w=750, h=300, OUTPUT_JPEGS= OUTPUT_JPEGS.1)
    
    # THE PLOT WITH AN CONSTATNT X-AXIS LENGTH
    plot_single_telo(x_length =max_length,seq_length = length(current_seq), subs =  analyze_list[[1]], serial_num = current_serial ,
                     seq_start = start(telo_irange),seq_end = end(telo_irange), save.it=T, main_title = title,  w=750, h=300, OUTPUT_JPEGS= OUTPUT_JPEGS)
    
    LargeDNAStringSet <- append(LargeDNAStringSet, values = sample_telomeres[i])
    current_serial <- current_serial + 1
  }
  
  # need to save the df in a file
  
  write.csv(x=df, file=OUTPUT_TELO_CSV)
  writeXStringSet(LargeDNAStringSet, OUTPUT_TELO_FASTA)
  message("Done!") #  now what's left is to extract the sequences from fasta to fasta using the read_names list file ( 3 files )
  
} # end of the function searchPatterns  




# need to create parApply for filter 
library("parallel")
filter_density <- function(sequence, patterns, min_density = 0.18){
  #'
  current_seq <- unlist(sequence)
  total_density <- 0 
  mp_all <- IRanges()# union of all the IRanges of all the patterns in the list 
  if(is.list(patterns)){
    patterns <- unique(patterns)  # make sure there are no dups
    for( pat in patterns){
      mp_all <- union.Vector(mp_all, matchPattern(pattern = pat, subject = unlist(sequence), max.mismatch = 0) )
    }
  }
  else{
    mp_all <- matchPattern(pattern = patterns, subject = unlist(sequence), max.mismatch = 0)
    mp_all <- union.Vector(mp_all, mp_all) # incase there are overlaps
  }
  total_density <-sum(width(mp_all)) / nchar(sequence)
  
  return( total_density >= min_density)
  
}


# need to correct the spelling for telorette
run_with_rc_and_filter <- function(samples,  patterns, output_dir, telorrete_pattern){
  #' @title: Run a search for Telomeric sequences on the reads   
  #' @description use rc to adjust for the patterns and barcode/telorette locatio ( should be at the last ~ 60-70 bases), filter out reads with no 
  #'              no telomeric pattern at the edge and run searchPatterns_withTelorette  
  #' @usage 
  #' @param samples: A DNAStringSet of reads
  #' @param patterns: The patterns for the telomere
  #' @param output_dir: The path for the output directory
  #' @param telorrete_pattern: The telorette pattern
  #' @return
  #' @examples
  
  
  if(!dir.exists(output_dir)){ # update  did it 
    dir.create(output_dir)
  }
  
  samps_1000 <- samples[width(samples) >= 1e3]
  samps_1000 <- Biostrings::reverseComplement(samps_1000)
  copies_of_r <- 10
  
  cl <- makeCluster(copies_of_r)
  samp_100 <- parLapply(cl, samps_1000, subseq, end = -67, width = 100)  # change to -(61+ just incase there are indels ( barcode_telorette == 61))
  stopCluster(cl)
  
  cl <- makeCluster(copies_of_r)
  logical_100 <- parSapply(cl, samp_100,  filter_density,patterns = patterns , min_density = 0.175)
  stopCluster(cl)
  names(logical_100) <- NULL
  
  samps_filtered <- samps_1000[logical_100]
  
  searchPatterns_withTelorette(samps_filtered, pattern_list = patterns, output_dir = output_dir , min_density = 0.18,
                               telorete_pattern = telorrete_pattern )
  
}


# to complete .....
# need to correct the spelling for telorette
run_with_rc_and_filter_10threadsSearchPattern <- function(samples,  patterns, output_dir, telorrete_pattern){
  #' @title: Run a search for Telomeric sequences on the reads   
  #' @description use rc to adjust for the patterns and barcode/telorette locatio ( should be at the last ~ 60-70 bases), filter out reads with no 
  #'              no telomeric pattern at the edge and run searchPatterns_withTelorette  
  #' @usage 
  #' @param samples: A DNAStringSet of reads
  #' @param patterns: The patterns for the telomere
  #' @param output_dir: The path for the output directory
  #' @param telorrete_pattern: The telorette pattern
  #' @return
  #' @examples
  
  if(!dir.exists(output_dir)){ # update  did it 
    dir.create(output_dir)
  }
  
  samps_1000 <- samples[width(samples) >= 1e3]
  samps_1000 <- Biostrings::reverseComplement(samps_1000)
  copies_of_r <- 10
  
  cl <- makeCluster(copies_of_r)
  samp_100 <- parLapply(cl, samps_1000, subseq, end = -67, width = 100)  # change to -(61+ just incase there are indels ( barcode_telorette == 61))
  stopCluster(cl)
  
  cl <- makeCluster(copies_of_r)
  logical_100 <- parSapply(cl, samp_100,  filter_density,patterns = patterns , min_density = 0.175)
  stopCluster(cl)
  names(logical_100) <- NULL
  
  samps_filtered <- samps_1000[logical_100]
  
  # now divide the samps_filtered to 10 sub-sets
  # crreate the dirs for plots...
  # use ParApply
  
  searchPatterns_withTelorette(samps_filtered, pattern_list = patterns, output_dir = output_dir , min_density = 0.18,
                               telorete_pattern = telorrete_pattern , serial_start =,  )
  
}



################## Arguments ######################################################

PATTERNS_LIST <- list("CCCTAA", "CCCTAG", "CCCTGA", "CCCTGG")  # CCCTRR
PATTERNS_LIST <- append(PATTERNS_LIST, list("CCTAAC", "CCTAGC", "CCTGAC", "CCTGGC")) # add CCTRRC
PATTERNS_LIST <- append(PATTERNS_LIST, list("CTAACC", "CTAGCC", "CTGACC", "CTGGCC")) # add CTRRCC
PATTERNS_LIST <- append(PATTERNS_LIST, list("TAACCC", "TAGCCC", "TGACCC", "TGGCCC")) # add TRRCCC
PATTERNS_LIST <- append(PATTERNS_LIST, list("AACCCT", "AGCCCT", "GACCCT", "GGCCCT")) # add RRCCCT
PATTERNS_LIST <- append(PATTERNS_LIST,list("ACCCTA", "GCCCTA", "ACCCTG", "GCCCTG"))  # add RCCCTR

patterns_dna <- lapply(PATTERNS_LIST, DNAString)
dna_rc_patterns <- lapply(patterns_dna, Biostrings::reverseComplement)
dna_rc_patterns <- lapply(dna_rc_patterns, toString)

the_telorete_pattern = "TGCTCCGTGCATCTCCAAGGTTCTAACC"
the_telorete_pattern <- toString(Biostrings::reverseComplement(DNAString(the_telorete_pattern)))
