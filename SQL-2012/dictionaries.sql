/*
	Columnstore Indexes Scripts Library for SQL Server 2012: 
	Dictionaries Analysis - Shows detailed information about the Columnstore Dictionaries
	Version: 1.4.2, December 2016

	Copyright 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/columnstore/), (http://www.oh22.is/)

	Licensed under the Apache License, Version: 1.4.2, December 2016 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

/*
Changes in 1.0.1:
	+ Added information about Id of the column in the dictionary, for better debugging
	+ Added ordering by the columnId
	+ Added new parameter to filter Dictionaries by the type: @showDictionaryType
	+ Added quotes for displaying the name of any tables correctly
	
Changes in 1.0.3:
	+ Added information about maximum sizes for the Global & Local dictionaries	
	+ Added new parameter for enabling the details of all available dictionaries	

Changes in 1.0.4:
	+ Added new parameter for filtering on the schema - @schemaName

Changes in 1.1.0:
	- Fixed error with row groups information returning back an error, because of the non-existing view (the code was copied from 2014 Version: 1.4.2, December 2016)

Changes in 1.2.0
	+ Included support for the temporary tables with Columnstore Indexes (global & local)	

Changes in 1.3.0
	- Fixed bug with non-existing DMV sys.column_store_row_groups
	* Removed Duplicate information on the ColumnId
	* Changed the title of the return information for the column from the SegmentId to the DictionaryId
	+ Added information on the Index Location (In-Memory or Disk-Based) and the respective filter
	+ Added information on the type of the Index (Clustered or Nonclustered) and the respective filter

Changes in 1.3.1
	- Added support for Databases with collations different to TempDB
*/
	
-- Params --
declare 
 	@showDetails bit = 1,								-- Enables showing the details of all Dictionaries
	@showWarningsOnly bit = 0,							-- Enables to filter out the dictionaries based on the Dictionary Size (@warningDictionarySizeInMB) and Entry Count (@warningEntryCount)
	@warningDictionarySizeInMB Decimal(8,2) = 6.,		-- The size of the dictionary, after which the dictionary should be selected. The value is in Megabytes 
	@warningEntryCount Int = 1000000,					-- Enables selecting of dictionaries with more than this number 
	@showAllTextDictionaries bit = 0,					-- Enables selecting all textual dictionaries independently from their warning status
	@showDictionaryType nvarchar(52) = NULL,			-- Enables to filter out dictionaries by type with possible values 'Local', 'Global' or NULL for both 
	@schemaName nvarchar(256) = NULL,					-- Allows to show data filtered down to the specified schema
	@tableName nvarchar(256) = NULL,					-- Allows to show data filtered down to 1 particular table
	@columnName nvarchar(256) = NULL,					-- Allows to filter out data base on 1 particular column name
	@indexLocation varchar(15) = NULL,					-- Allows to filter Columnstore Indexes based on their location: Disk-Based & In-Memory
	@indexType char(2) = NULL							-- Allows to filter Columnstore Indexes by their type, with possible values (CC for 'Clustered', NC for 'Nonclustered' or NULL for both)
-- end of --

declare @table_object_id int = NULL;

if (@tableName is not NULL )
	set @table_object_id = isnull(object_id(@tableName),-1);
else 
	set @table_object_id = NULL;

--------------------------------------------------------------------------------------------------------------------
declare @SQLServerVersion nvarchar(128) = cast(SERVERPROPERTY('ProductVersion: 1.4.2, December 2016') as NVARCHAR(128)), 
		@SQLServerEdition nvarchar(128) = cast(SERVERPROPERTY('Edition') as NVARCHAR(128)),
		@SQLServerBuild smallint = NULL;
declare @errorMessage nvarchar(512);

-- Ensure that we are running SQL Server 2012
if substring(@SQLServerVersion,1,CHARINDEX('.',@SQLServerVersion)-1) <> N'11'
begin
	set @errorMessage = (N'You are not running a SQL Server 2012. Your SQL Server Version: 1.4.2, December 2016 is ' + @SQLServerVersion);
	Throw 51000, @errorMessage, 1;
end

if SERVERPROPERTY('EngineEdition') <> 3 
begin
	set @errorMessage = (N'Your SQL Server 2012 Edition is not an Enterprise or a Developer Edition: Your are running a ' + @SQLServerEdition);
	Throw 51000, @errorMessage, 1;
end

--------------------------------------------------------------------------------------------------------------------
set nocount on;

SELECT QuoteName(object_schema_name(i.object_id)) + '.' + QuoteName(object_name(i.object_id)) as 'TableName', 
		case i.type when 5 then 'Clustered' when 6 then 'Nonclustered' end as 'Type',
		case i.data_space_id when 0 then 'In-Memory' else 'Disk-Based' end as [Location],	
		p.partition_number as 'Partition',
		(select count(distinct rg.segment_id) from sys.column_store_segments rg
				where rg.hobt_id = p.hobt_id and rg.partition_id = p.partition_id) as 'RowGroups',
		count(csd.column_id) as 'Dictionaries', 
		sum(csd.entry_count) as 'EntriesCount',
		min(p.rows) as 'Rows Serving',
		cast( SUM(csd.on_disk_size)/(1024.0*1024.0) as Decimal(8,3)) as 'Total Size in MB',
		cast( MAX(case dictionary_id when 0 then csd.on_disk_size else 0 end)/(1024.0*1024.0) as Decimal(8,3)) as 'Max Global Size in MB',
		cast( MAX(case dictionary_id when 0 then 0 else csd.on_disk_size end)/(1024.0*1024.0) as Decimal(8,3)) as 'Max Local Size in MB'
    FROM sys.indexes AS i
		inner join sys.partitions AS p
			on i.object_id = p.object_id 
		inner join sys.column_store_dictionaries AS csd
			on csd.hobt_id = p.hobt_id and csd.partition_id = p.partition_id
    where i.type in (5,6)
		and (@tableName is null or object_name (i.object_id) like '%' + @tableName + '%')
		and (@schemaName is null or object_schema_name(i.object_id) = @schemaName)
		and i.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else i.data_space_id end, i.data_space_id )
		and case @indexType when 'CC' then 5 when 'NC' then 6 else i.type end = i.type
	group by object_schema_name(i.object_id) + '.' + object_name(i.object_id), i.object_id, p.hobt_id, p.partition_number, p.partition_id, i.data_space_id, i.type
union all
SELECT QuoteName(object_schema_name(i.object_id,db_id('tempdb'))) + '.' + QuoteName(object_name(i.object_id,db_id('tempdb'))) as 'TableName', 
		case i.type when 5 then 'Clustered' when 6 then 'Nonclustered' end as 'Type',
		case i.data_space_id when 0 then 'In-Memory' else 'Disk-Based' end as [Location],	
		p.partition_number as 'Partition',
		(select count(distinct rg.segment_id) from tempdb.sys.column_store_segments rg
				where rg.hobt_id = p.hobt_id and rg.partition_id = p.partition_id) as 'RowGroups',
		count(csd.column_id) as 'Dictionaries', 
		sum(csd.entry_count) as 'EntriesCount',
		min(p.rows) as 'Rows Serving',
		cast( SUM(csd.on_disk_size)/(1024.0*1024.0) as Decimal(8,3)) as 'Total Size in MB',
		cast( MAX(case dictionary_id when 0 then csd.on_disk_size else 0 end)/(1024.0*1024.0) as Decimal(8,3)) as 'Max Global Size in MB',
		cast( MAX(case dictionary_id when 0 then 0 else csd.on_disk_size end)/(1024.0*1024.0) as Decimal(8,3)) as 'Max Local Size in MB'
    FROM tempdb.sys.indexes AS i
		inner join tempdb.sys.partitions AS p
			on i.object_id = p.object_id 
		inner join tempdb.sys.column_store_dictionaries AS csd
			on csd.hobt_id = p.hobt_id and csd.partition_id = p.partition_id
    where i.type in (5,6)
		and (@tableName is null or object_name (i.object_id,db_id('tempdb')) like '%' + @tableName + '%')
		and (@schemaName is null or object_schema_name(i.object_id,db_id('tempdb')) = @schemaName)
		and i.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else i.data_space_id end, i.data_space_id )
		and case @indexType when 'CC' then 5 when 'NC' then 6 else i.type end = i.type
	group by object_schema_name(i.object_id,db_id('tempdb')) + '.' + object_name(i.object_id,db_id('tempdb')), i.object_id, p.hobt_id, p.partition_id, p.partition_number, i.data_space_id, i.type;


if @showDetails = 1
	select QuoteName(object_schema_name(part.object_id)) + '.' + QuoteName(object_name(part.object_id)) as 'TableName',
			ind.name as 'IndexName', 
			part.partition_number as 'Partition',
			cols.name as ColumnName, 
			dict.column_id as [ColumnId],
			dict.dictionary_id as 'SegmentId',
			tp.name as ColumnType,
			case dictionary_id when 0 then 'Global' else 'Local' end as 'Type', 
			part.rows as 'Rows Serving', 
			entry_count as 'Entry Count', 
			cast( on_disk_size / 1024. / 1024. as Decimal(8,2)) 'SizeInMb'
	from sys.column_store_dictionaries dict
		inner join sys.partitions part
			ON dict.hobt_id = part.hobt_id and dict.partition_id = part.partition_id
		inner join sys.indexes ind
			on part.object_id = ind.object_id and part.index_id = ind.index_id
		inner join sys.columns cols
			on part.object_id = cols.object_id and dict.column_id = cols.column_id
		inner join sys.types tp
			on cols.system_type_id = tp.system_type_id and cols.user_type_id = tp.user_type_id
	where 
		(( @showWarningsOnly = 1 
			AND 
			( cast( on_disk_size / 1024. / 1024. as Decimal(8,2)) > @warningDictionarySizeInMB OR
				entry_count > @warningEntryCount
			)
		) OR @showWarningsOnly = 0 )
		AND
		(( @showAllTextDictionaries = 1 
			AND
			case tp.name 
				when 'char' then 1
				when 'nchar' then 1
				when 'varchar' then 1
				when 'nvarchar' then 1
				when 'sysname' then 1
			end = 1
		) OR @showAllTextDictionaries = 0 )
		and (@tableName is null or object_name (ind.object_id) like '%' + @tableName + '%')
		and (@schemaName is null or object_schema_name(ind.object_id) = @schemaName)
		and cols.name = isnull(@columnName,cols.name)
		and case dictionary_id when 0 then 'Global' else 'Local' end = isnull(@showDictionaryType, case dictionary_id when 0 then 'Global' else 'Local' end)
		and ind.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else ind.data_space_id end, ind.data_space_id )
		and case @indexType when 'CC' then 5 when 'NC' then 6 else ind.type end = ind.type
	union all
	select QuoteName(object_schema_name(part.object_id,db_id('tempdb'))) + '.' + QuoteName(object_name(part.object_id,db_id('tempdb'))) as 'TableName',
			ind.name COLLATE DATABASE_DEFAULT as 'IndexName', 
			part.partition_number as 'Partition',
			cols.name COLLATE DATABASE_DEFAULT as ColumnName, 
			dict.column_id as [ColumnId],
			dict.dictionary_id as 'SegmentId',
			tp.name COLLATE DATABASE_DEFAULT as ColumnType,
			case dictionary_id when 0 then 'Global' else 'Local' end as 'Type', 
			part.rows as 'Rows Serving', 
			entry_count as 'Entry Count', 
			cast( on_disk_size / 1024. / 1024. as Decimal(8,2)) 'SizeInMb'
	from tempdb.sys.column_store_dictionaries dict
		inner join tempdb.sys.partitions part
			ON dict.hobt_id = part.hobt_id and dict.partition_id = part.partition_id
		inner join tempdb.sys.indexes ind
			on part.object_id = ind.object_id and part.index_id = ind.index_id
		inner join tempdb.sys.columns cols
			on part.object_id = cols.object_id and dict.column_id = cols.column_id
		inner join tempdb.sys.types tp
			on cols.system_type_id = tp.system_type_id and cols.user_type_id = tp.user_type_id
	where 
		(( @showWarningsOnly = 1 
			AND 
			( cast( on_disk_size / 1024. / 1024. as Decimal(8,2)) > @warningDictionarySizeInMB OR
				entry_count > @warningEntryCount
			)
		) OR @showWarningsOnly = 0 )
		AND
		(( @showAllTextDictionaries = 1 
			AND
			case tp.name 
				when 'char' then 1
				when 'nchar' then 1
				when 'varchar' then 1
				when 'nvarchar' then 1
				when 'sysname' then 1
			end = 1
		) OR @showAllTextDictionaries = 0 )
		and (@tableName is null or object_name (ind.object_id,db_id('tempdb')) like '%' + @tableName + '%')
		and (@schemaName is null or object_schema_name(ind.object_id,db_id('tempdb')) = @schemaName)
		and cols.name = isnull(@columnName,cols.name)
		and case dictionary_id when 0 then 'Global' else 'Local' end = isnull(@showDictionaryType, case dictionary_id when 0 then 'Global' else 'Local' end)
		and ind.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else ind.data_space_id end, ind.data_space_id )
		and case @indexType when 'CC' then 5 when 'NC' then 6 else ind.type end = ind.type
		order by TableName, ind.name, part.partition_number, dict.column_id;

