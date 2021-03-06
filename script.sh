#!/bin/bash
# set -e


ROOT_DIR=/tmp
TOOLS_DIR=$ROOT_DIR/tpcds-kit/tools
DATA_DIR=$ROOT_DIR/data
QUERIES_DIR=$ROOT_DIR/queries
OUTPUT_DIR=$ROOT_DIR/output


# Function to debug and record the timestamp of each step of the script
log() {
	echo  `date +"%Y-%m-%d %H-%M-%S"` $1
}

SCALE_FACTOR=${SCALE_FACTOR:-1}
DATABASE=$MYSQL_DATABASE

generate_data() {
	log "------------ Generating data! -----------------------"
	mkdir -p $DATA_DIR && \
	cd $TOOLS_DIR && \
	./dsdgen -SCALE ${SCALE_FACTOR} -DIR $DATA_DIR -FORCE -VERBOSE
}

create_db() {
	log "------------ Setting-up database! -------------------"
	mysql -uroot -e "DROP DATABASE IF EXISTS ${DATABASE}" && \
	mysql -uroot -e "CREATE DATABASE ${DATABASE}" && \
	mysql -uroot $DATABASE < $TOOLS_DIR/tpcds.sql
}

# For every .dat file generated by dsdgen, converts empty values to '\N', save in a .dsv file and
# then upload the latter using mysqlimport. Then runs the alter tables from the file with constraints.	
load_db() {
	log "------------ Loading data into database! ------------"
	
	# for every generated data file
	# ls -Sr $DATA_DIR/*.dat | while read dat_file; do
	# 	# creates dsv file
	# 	table=`basename $dat_file .dat`
	# 	dsv_file=$DATA_DIR/$table.dsv
		
	# 	log "----------------- ${table}"
		
	# 	# converts empty values to '\N' (NULL)
	# 	sed -e 's#||#|\\N|#g' -e 's#^|#\\N|#g' -e 's#||#|\\N|#g' $dat_file > $dsv_file # converts empty values to '\N' (NULL)

	# 	# splits into 10 MB files
	# 	split -C 10M $dsv_file $DATA_DIR/$table.split_
		
	# 	# import splitted files using 8 threads
	# 	ls $DATA_DIR/$table.split_* | xargs -P8 -I % sh -c 'mysqlimport -uroot --local --default-character-set=latin1 --replace --silent --fields-terminated-by='"'"'|'"' $DATABASE "'% && rm -f %;'
	# 	rm -f $dsv_file
	# done

	log "------------ Apply constraints to database! ---------"
	cat $TOOLS_DIR/tpcds_ri.sql | egrep -v "(^--.*|^$)" | xargs -P8 -I % mysql -uroot $DATABASE -e %
}

# Generate the queries using dsqgen and splits the output file into individual query files for
# every template. It also saves a file with the query order.
generate_queries() {
	log "------------ Generating queries! --------------------"
	mkdir -p $QUERIES_DIR && \
	cd $TOOLS_DIR && \
	./dsqgen -DIRECTORY ../query_templates/ -INPUT ../query_templates/mysql_templates.lst -QUIET Y -SCALE ${SCALE_FACTOR} -OUTPUT_DIR $QUERIES_DIR -DIALECT mysql 
	awk -v dir="$QUERIES_DIR" '/^-- start query/{close (prev); name=$NF; gsub(/tpl/, "sql", name);}{prev=dir"/"name; print > (prev);}' $QUERIES_DIR"/query_0.sql"
	awk -v dir="$QUERIES_DIR" '/^-- start query/{name=$NF; gsub(/tpl/, "sql", name); print dir"/"name}' $QUERIES_DIR"/query_0.sql" > $QUERIES_DIR/query_order.txt
	log "----------------- "$(grep '' -c $QUERIES_DIR/query_order.txt)" queries generated!"
}

run_queries() {
	log "------------ Running queries! -----------------------"
	mkdir -p $OUTPUT_DIR && mkdir -p $OUTPUT_DIR/res && mkdir -p $OUTPUT_DIR/err # create the output folders
	
	while read query_file; do # for every query considering the query order
		((i++))
		log "----------------- ${i} - "`basename $query_file .sql`
		
		RESULT_FILE="$OUTPUT_DIR/res/`basename $query_file .sql`.res"
		ERROR_FILE="$OUTPUT_DIR/err/`basename $query_file .sql`.err"
		MYSQL_LOG_FILE="/var/log/mysql/`basename $query_file .sql`.log"
		
		# create/truncate and set the variable for log file
		rm -f $MYSQL_LOG_FILE
		:> $MYSQL_LOG_FILE
		chown mysql:mysql $MYSQL_LOG_FILE
		mysql -uroot -e "SET GLOBAL slow_query_log_file = '${MYSQL_LOG_FILE}';"
		
		# execute the query
		mysql -uroot $DATABASE < $query_file > $RESULT_FILE 2> $ERROR_FILE
		
		# remove output files if they are empty
		[ -s "$ERROR_FILE" ] && log "---------------------- ERROR"
		[ -s "$ERROR_FILE" ] || rm -f "$ERROR_FILE"
		[ -s "$MYSQL_LOG_FILE" ] || rm -f "$MYSQL_LOG_FILE"
		[ -s "$RESULT_FILE" ] || rm -f "$RESULT_FILE"

	done < $QUERIES_DIR/query_order.txt
}



generate_data && \
generate_queries && \
create_db && \
load_db && \
run_queries

log "------------ DONE! ----------------------------------"
