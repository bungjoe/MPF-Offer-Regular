CREATE OR REPLACE PROCEDURE CAMP_SMS_FF_GET_BASE AS
    DT_CURRENT TIMESTAMP;           CNT_NEW_LEADS NUMBER;       CNT_TOTAL_LEADS NUMBER;     CNT_APP_LEADS NUMBER;
    CNT_INBOUND_LEADS NUMBER;       CNT_LANDING_LEADS NUMBER;   CNT_COMBINE_LEADS NUMBER;   ADDITIONAL NUMBER;

PROCEDURE PSTATS( ACTABLE VARCHAR2, ANPERC NUMBER DEFAULT 0.01) IS
BEGIN
    AP_PUBLIC.CORE_LOG_PKG.PSTART( 'Stat:'||UPPER(ACTABLE) );
    DBMS_STATS.GATHER_TABLE_STATS( OWNNAME => 'AP_CRM', TABNAME => ACTABLE,ESTIMATE_PERCENT => ANPERC );
    AP_PUBLIC.CORE_LOG_PKG.PEND;
END;
PROCEDURE PTRUNCATE( ACTABLE VARCHAR2) IS
BEGIN
    AP_PUBLIC.CORE_LOG_PKG.PSTART( 'Trunc:'||UPPER(ACTABLE) );
    EXECUTE IMMEDIATE 'TRUNCATE TABLE AP_CRM.'||UPPER(ACTABLE) ;
    AP_PUBLIC.CORE_LOG_PKG.PEND ;
END;
BEGIN
    AP_PUBLIC.CORE_LOG_PKG.PINIT( 'AP_CRM', 'CAMP_SMS_FF_GET_BASE');
    DT_CURRENT := SYSDATE;

IF TRUNC(DT_CURRENT) = '21-SEP-2018' THEN

    PTRUNCATE('GTT_CAMP_PTB_POPULATION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_PTB_POPULATION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_PTB_POPULATION
    SELECT CAMPAIGN_ID,	DATE_VALID_FROM,	DATE_VALID_TO,	SKP_CLIENT,	ID_CUID,	PILOT_FLAG,	DECILE,	SCORE,	CALL_STRATEGY,	DTIME_INSERT
    FROM PTB_POPULATION WHERE CAMPAIGN_ID LIKE TO_CHAR(SYSDATE, 'YYMM')
    UNION ALL
    SELECT TO_CHAR(SYSDATE, 'YYMM') CAMPAIGN_ID,	DATE_VALID_FROM,	DATE_VALID_TO,	SKP_CLIENT,	ID_CUID,	PILOT_FLAG,	DECILE,	SCORE,	CALL_STRATEGY,	DTIME_INSERT
    FROM PTB_POPULATION 
    WHERE CAMPAIGN_ID LIKE TO_CHAR(SYSDATE, 'YYMM')-1 
          AND ID_CUID IN 
              (SELECT ID_CUID FROM AP_RISK.ELIGIBILITY_BASE WHERE CAMP_MONTH_CALC = TRUNC(SYSDATE, 'MM')-1 AND ELIGIBLE_FINAL_FLAG = 1
              AND ID_CUID NOT IN (SELECT ID_CUID FROM PTB_POPULATION WHERE CAMPAIGN_ID LIKE TO_CHAR(SYSDATE, 'YYMM')))
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_PTB_POPULATION');
    
    PTRUNCATE('GTT_CAMP_CALL_TO_ACTION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_CALL_TO_ACTION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_CALL_TO_ACTION
    SELECT DISTINCT ID_CUID, CALL_TO_ACTION FROM CAMP_SMS_FF_BASE
    WHERE (ID_CUID, DTIME_INSERTED) IN (SELECT ID_CUID, MAX(DTIME_INSERTED) FROM CAMP_SMS_FF_BASE GROUP BY ID_CUID);
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_CALL_TO_ACTION');
    
    PTRUNCATE('GTT_CAMP_EMAIL');
    INSERT INTO GTT_CAMP_EMAIL
    SELECT ID_CUID, EMAIL CLIENT_EMAIL
    FROM (SELECT ID_CUID, EMAIL, ROW_NUMBER() OVER (PARTITION BY ID_CUID ORDER BY EMAIL) RN
          FROM AP_CRM.V_CAMP_FINAL_EMAIL_ADDR 
          WHERE EMAIL IS NOT NULL
                AND REGEXP_LIKE (EMAIL, '^[A-Za-z]+[A-Za-z0-9._]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$')
                AND ID_CUID IN (SELECT ID_CUID FROM AP_RISK.ELIGIBILITY_BASE WHERE CAMP_MONTH_CALC = TRUNC(SYSDATE, 'MM')-1 AND ELIGIBLE_FINAL_FLAG = 1) 
         )
    WHERE RN = 1
    ;
    COMMIT;    

    PTRUNCATE('GTT_CAMP_SMS_POPULATION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_SMS_POPULATION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_SMS_POPULATION
    SELECT TO_CHAR(DT_CURRENT, 'YYMM') CAMPAIGN_ID,                         DT_CURRENT DTIME_INSERTED,      
          BASE.SKP_CLIENT,              BASE.ID_CUID,                       BASE.ELIGIBLE_FINAL_FLAG, 
          BASE.VALID_FROM,              BASE.VALID_TO,                      BASE.NAME_FULL,             BASE.NAME_FIRST,
          BASE.NAME_MIDDLE,             BASE.NAME_LAST,                     BASE.DATE_BIRTH,
          BASE.GENDER,                  BASE.PRIORITY_ACTUAL,               BASE.CNT_ACTIVE_CONTRACTS,
          BASE.CA_LIMIT_FINAL_UPDATED,  BASE.ANNUITY_LIMIT_FINAL_UPDATED,   BASE.PILOT_NAME,             
          BASE.PRICING_STRATEGY,        BASE.RISK_BAND,                     BASE.RBP_SEGMENT_TEMP,      BASE.INTEREST_RATE,
          BASE.MAX_TENOR,               PTB.DECILE,                         NVL(CTA.CALL_TO_ACTION, 'NEW LEADS') CALL_TO_ACTION,
          CASE WHEN CTA.CALL_TO_ACTION IS NULL 
               THEN NTILE(100) OVER(PARTITION BY CASE WHEN EML.ID_CUID IS NOT NULL THEN 'Y' ELSE 'N' END, NVL(DLY.FLAG_STILL_ELIGIBLE, 'Y'), PTB.DECILE ORDER BY MOD(BASE.ID_CUID, 6607)/6606)
               ELSE NULL
          END NTILE_VALUE
    FROM AP_RISK.ELIGIBILITY_BASE BASE
    LEFT JOIN GTT_CAMP_PTB_POPULATION PTB ON BASE.ID_CUID = PTB.ID_CUID
    LEFT JOIN GTT_CAMP_CALL_TO_ACTION CTA ON BASE.ID_CUID = CTA.ID_CUID
    LEFT JOIN CAMP_ELIG_DAILY_CHECK DLY ON BASE.ID_CUID = DLY.ID_CUID AND TRUNC(SYSDATE) BETWEEN DLY.DATE_VALID_FROM AND DLY.DATE_VALID_TO
    LEFT JOIN GTT_CAMP_EMAIL EML ON BASE.ID_CUID = EML.ID_CUID
    WHERE BASE.CAMP_MONTH_CALC = TRUNC(SYSDATE, 'MM')-1
          AND BASE.ELIGIBLE_FINAL_FLAG = 1
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_SMS_POPULATION');
    
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into CAMP_SMS_FF_BASE');
    INSERT /*+ APPEND PARALLEL(4) */ INTO CAMP_SMS_FF_BASE
    SELECT POP.CAMPAIGN_ID,	                    POP.DTIME_INSERTED,	    POP.SKP_CLIENT,	            POP.ID_CUID,	
           POP.ELIGIBLE_FINAL_FLAG,	            POP.VALID_FROM,	        POP.VALID_TO,	            POP.NAME_FULL,	
           POP.NAME_FIRST,	                    POP.NAME_MIDDLE,	    POP.NAME_LAST,	            POP.DATE_BIRTH,	
           POP.GENDER,	                        POP.PRIORITY_ACTUAL,	POP.CNT_ACTIVE_CONTRACTS,	POP.CA_LIMIT_FINAL_UPDATED,	
           POP.ANNUITY_LIMIT_FINAL_UPDATED,	    POP.PILOT_NAME,	        POP.PRICING_STRATEGY,	    POP.RISK_BAND,	
           POP.RBP_SEGMENT_TEMP,	            POP.INTEREST_RATE,	    POP.MAX_TENOR,	            POP.DECILE,	                POP.NTILE_VALUE,
           CASE WHEN NTILE_VALUE BETWEEN 1 AND 25 THEN 'APP'
                WHEN NTILE_VALUE BETWEEN 26 AND 50 THEN 'INBOUND'
                WHEN NTILE_VALUE BETWEEN 51 AND 65 THEN 'LANDING'
                ELSE 'COMBINE'
            END CALL_TO_ACTION
    FROM GTT_CAMP_SMS_POPULATION POP
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_SMS_POPULATION');

ELSE 

--    AP_PUBLIC.CORE_LOG_PKG.pStart('INS:gtt_camp_elig_base2');
--    INSERT /*+ APPEND PARALLEL(5) */ into gtt_camp_elig_base2
--    select 
--         eb.skp_client                                     ,eb.id_cuid
--        ,eb.name_full                                      ,eb.name_first 
--        ,eb.name_middle                                    ,eb.name_last
--        ,eb.date_birth                                     ,eb.name_birth_place
--        ,eb.gender gender                                  ,eb.code_employment_type code_employment_type
--        ,eb.CODE_EDUCATION_TYPE                            ,eb.code_employer_industry
--        ,eb.main_income                                    ,eb.OTHER_INCOME
--        ,eb.AMT_EXPENSE_DEBT                               ,eb.SUM_AMT_ANNUITY_ACTIVE
--        ,eb.total_paid_amount                              ,eb.total_overpaid_amount
--        ,eb.dpd_ever                                       ,eb.dpd_3m
--        ,eb.dpd_actual                                     ,null max_pilot_flag
--        ,eb.NUMBER_OF_CL_CONTRACTS                         ,null PREV_PRICING_STRATEGY
--        ,eb.pricing_strategy                               ,eb.valid_from
--        ,eb.valid_to                                       ,eb.risk_band
--        ,eb.rbp_segment_temp                               ,eb.INTEREST_RATE
--        ,eb.max_tenor                                      ,eb.camp_type
--        ,eb.x_sell_flag                                    ,eb.score
--        ,eb.ANNUITY_LIMIT_FINAL_UPDATED                    ,eb.CA_LIMIT_FINAL_UPDATED
--        ,eb.priority_actual                                ,eb.eligible_final_flag
--        ,eb.sid_result                                     ,eb.pilot_name
--        ,eb.score_pd                                       ,EB.CNT_ACTIVE_CONTRACTS 
--        ,eb.fl_current_eligibility                         ,EB.REASON_NOT_ELIG
--        /*,eb.camp_month_calc*/                            
--				,row_number() over (partition by eb.skp_client order by eb.valid_from desc) nums
--        from ap_risk.eligibility_base eb
--        where valid_from = TRUNC(DT_CURRENT, 'MM')
--              AND eb.eligible_final_flag = 1
--        ; 
--		AP_PUBLIC.CORE_LOG_PKG.pEnd;
--		commit;
--		pStats('gtt_camp_elig_base2');
    
    PTRUNCATE('GTT_CAMP_PTB_POPULATION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_PTB_POPULATION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_PTB_POPULATION
    SELECT CAMPAIGN_ID,	DATE_VALID_FROM,	DATE_VALID_TO,	SKP_CLIENT,	ID_CUID,	PILOT_FLAG,	DECILE,	SCORE,	CALL_STRATEGY,	DTIME_INSERT
    FROM PTB_POPULATION WHERE CAMPAIGN_ID LIKE TO_CHAR(DT_CURRENT, 'YYMM')
    UNION ALL
    SELECT TO_CHAR(DT_CURRENT, 'YYMM') CAMPAIGN_ID,	DATE_VALID_FROM,	DATE_VALID_TO,	SKP_CLIENT,	ID_CUID,	PILOT_FLAG,	DECILE,	SCORE,	CALL_STRATEGY,	DTIME_INSERT
    FROM PTB_POPULATION 
    WHERE CAMPAIGN_ID LIKE TO_CHAR(DT_CURRENT, 'YYMM')-1 
          AND ID_CUID IN 
              (SELECT ID_CUID FROM AP_RISK.ELIGIBILITY_BASE WHERE CAMP_MONTH_CALC = TRUNC(DT_CURRENT, 'MM')-1 AND ELIGIBLE_FINAL_FLAG = 1
               AND ID_CUID NOT IN (SELECT ID_CUID FROM PTB_POPULATION WHERE CAMPAIGN_ID LIKE TO_CHAR(DT_CURRENT, 'YYMM')))
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_PTB_POPULATION');
    
    PTRUNCATE('GTT_CAMP_CALL_TO_ACTION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_CALL_TO_ACTION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_CALL_TO_ACTION
    SELECT DISTINCT ID_CUID, CALL_TO_ACTION FROM CAMP_SMS_FF_BASE
    WHERE (ID_CUID, DTIME_INSERTED) IN (SELECT ID_CUID, MAX(DTIME_INSERTED) FROM CAMP_SMS_FF_BASE GROUP BY ID_CUID);
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_CALL_TO_ACTION');
    
    PTRUNCATE('GTT_CAMP_EMAIL');
    INSERT INTO GTT_CAMP_EMAIL
    SELECT ID_CUID, EMAIL CLIENT_EMAIL
    FROM (SELECT ID_CUID, EMAIL, ROW_NUMBER() OVER (PARTITION BY ID_CUID ORDER BY EMAIL) RN
          FROM AP_CRM.V_CAMP_FINAL_EMAIL_ADDR 
          WHERE EMAIL IS NOT NULL
                AND REGEXP_LIKE (EMAIL, '^[A-Za-z]+[A-Za-z0-9._]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$')
                AND ID_CUID IN (SELECT ID_CUID FROM AP_RISK.ELIGIBILITY_BASE WHERE CAMP_MONTH_CALC = TRUNC(DT_CURRENT, 'MM')-1 AND ELIGIBLE_FINAL_FLAG = 1) 
         )
    WHERE RN = 1
    ;
    COMMIT;     

    PTRUNCATE('GTT_CAMP_SMS_POPULATION');
    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into GTT_CAMP_SMS_POPULATION');
    INSERT /*+ APPEND PARALLEL(4) */ INTO GTT_CAMP_SMS_POPULATION
    SELECT TO_CHAR(DT_CURRENT, 'YYMM') CAMPAIGN_ID,                         DT_CURRENT DTIME_INSERTED,      
          BASE.SKP_CLIENT,              BASE.ID_CUID,                       BASE.ELIGIBLE_FINAL_FLAG, 
          BASE.VALID_FROM,              BASE.VALID_TO,                      BASE.NAME_FULL,             BASE.NAME_FIRST,
          BASE.NAME_MIDDLE,             BASE.NAME_LAST,                     BASE.DATE_BIRTH,
          BASE.GENDER,                  BASE.PRIORITY_ACTUAL,               BASE.CNT_ACTIVE_CONTRACTS,
          BASE.CA_LIMIT_FINAL_UPDATED,  BASE.ANNUITY_LIMIT_FINAL_UPDATED,   BASE.PILOT_NAME,             
          BASE.PRICING_STRATEGY,        BASE.RISK_BAND,                     BASE.RBP_SEGMENT_TEMP,      BASE.INTEREST_RATE,
          BASE.MAX_TENOR,               PTB.DECILE,                         NVL(CTA.CALL_TO_ACTION, 'NEW LEADS') CALL_TO_ACTION,
          CASE WHEN CTA.CALL_TO_ACTION IS NULL 
               THEN NTILE(100) OVER(PARTITION BY CASE WHEN EML.ID_CUID IS NOT NULL THEN 'Y' ELSE 'N' END, NVL(DLY.FLAG_STILL_ELIGIBLE, 'Y'), PTB.DECILE ORDER BY MOD(BASE.ID_CUID, 6607)/6606)
               ELSE NULL
          END NTILE_VALUE
    FROM AP_RISK.ELIGIBILITY_BASE BASE
    LEFT JOIN GTT_CAMP_PTB_POPULATION PTB ON BASE.ID_CUID = PTB.ID_CUID
    LEFT JOIN GTT_CAMP_CALL_TO_ACTION CTA ON BASE.ID_CUID = CTA.ID_CUID
    LEFT JOIN CAMP_ELIG_DAILY_CHECK DLY ON BASE.ID_CUID = DLY.ID_CUID AND TRUNC(DT_CURRENT) BETWEEN DLY.DATE_VALID_FROM AND DLY.DATE_VALID_TO
    LEFT JOIN GTT_CAMP_EMAIL EML ON BASE.ID_CUID = EML.ID_CUID
    WHERE BASE.CAMP_MONTH_CALC = TRUNC(DT_CURRENT, 'MM')-1
          AND BASE.ELIGIBLE_FINAL_FLAG = 1
          AND BASE.ID_CUID NOT IN (SELECT ID_CUID FROM CAMP_SMS_FF_BASE WHERE CAMPAIGN_ID LIKE TO_CHAR(DT_CURRENT, 'YYMM'))
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_SMS_POPULATION');
    
    SELECT COUNT(1) INTO ADDITIONAL FROM GTT_CAMP_SMS_POPULATION;
    
    IF ADDITIONAL = 0 THEN
       GOTO FINISH_LINE;
    END IF;
    
    SELECT COUNT(1) INTO CNT_TOTAL_LEADS FROM GTT_CAMP_SMS_POPULATION;
    SELECT COUNT(1) INTO CNT_NEW_LEADS FROM GTT_CAMP_SMS_POPULATION WHERE CALL_TO_ACTION = 'NEW LEADS';

    SELECT CASE WHEN CNT_NEW_LEADS = 0 THEN 25
                ELSE ROUND((((0.25*CNT_TOTAL_LEADS)-COUNT(1))/CNT_NEW_LEADS)*100) END INTO CNT_APP_LEADS 
    FROM GTT_CAMP_SMS_POPULATION
    WHERE CALL_TO_ACTION = 'APP'
    GROUP BY CALL_TO_ACTION;
    
    SELECT CASE WHEN CNT_NEW_LEADS = 0 THEN 25
                ELSE ROUND((((0.25*CNT_TOTAL_LEADS)-COUNT(1))/CNT_NEW_LEADS)*100) END INTO CNT_INBOUND_LEADS 
    FROM GTT_CAMP_SMS_POPULATION
    WHERE CALL_TO_ACTION = 'INBOUND'
    GROUP BY CALL_TO_ACTION;
    
    SELECT CASE WHEN CNT_NEW_LEADS = 0 THEN 15
                ELSE ROUND((((0.15*CNT_TOTAL_LEADS)-COUNT(1))/CNT_NEW_LEADS)*100) END INTO CNT_LANDING_LEADS 
    FROM GTT_CAMP_SMS_POPULATION
    WHERE CALL_TO_ACTION = 'LANDING'
    GROUP BY CALL_TO_ACTION;
    
    SELECT CASE WHEN CNT_NEW_LEADS = 0 THEN 35
                ELSE ROUND((((0.35*CNT_TOTAL_LEADS)-COUNT(1))/CNT_NEW_LEADS)*100) END  INTO CNT_COMBINE_LEADS 
    FROM GTT_CAMP_SMS_POPULATION
    WHERE CALL_TO_ACTION = 'COMBINE'
    GROUP BY CALL_TO_ACTION;

    AP_PUBLIC.CORE_LOG_PKG.PSTART('Insert into CAMP_SMS_FF_BASE');
    INSERT /*+ APPEND PARALLEL(4) */ INTO CAMP_SMS_FF_BASE
    SELECT POP.CAMPAIGN_ID,	                    POP.DTIME_INSERTED,	    POP.SKP_CLIENT,	            POP.ID_CUID,	
           POP.ELIGIBLE_FINAL_FLAG,	            POP.VALID_FROM,	        POP.VALID_TO,	            POP.NAME_FULL,	
           POP.NAME_FIRST,	                    POP.NAME_MIDDLE,	    POP.NAME_LAST,	            POP.DATE_BIRTH,	
           POP.GENDER,	                        POP.PRIORITY_ACTUAL,	POP.CNT_ACTIVE_CONTRACTS,	POP.CA_LIMIT_FINAL_UPDATED,	
           POP.ANNUITY_LIMIT_FINAL_UPDATED,	    POP.PILOT_NAME,	        POP.PRICING_STRATEGY,	    POP.RISK_BAND,	
           POP.RBP_SEGMENT_TEMP,	            POP.INTEREST_RATE,	    POP.MAX_TENOR,	            POP.DECILE,	                POP.NTILE_VALUE,
           CASE WHEN POP.NTILE_VALUE IS NOT NULL THEN
               (CASE WHEN POP.NTILE_VALUE BETWEEN 1 AND CNT_APP_LEADS THEN 'APP'
                     WHEN POP.NTILE_VALUE BETWEEN (CNT_APP_LEADS+1) AND (CNT_APP_LEADS+CNT_INBOUND_LEADS) THEN 'INBOUND'
                     WHEN POP.NTILE_VALUE BETWEEN (CNT_APP_LEADS+CNT_INBOUND_LEADS+1) AND (CNT_APP_LEADS+CNT_INBOUND_LEADS+CNT_LANDING_LEADS) THEN 'LANDING'
                     WHEN POP.NTILE_VALUE BETWEEN (CNT_APP_LEADS+CNT_INBOUND_LEADS+CNT_LANDING_LEADS+1) AND (CNT_APP_LEADS+CNT_INBOUND_LEADS+CNT_LANDING_LEADS+CNT_COMBINE_LEADS) THEN 'COMBINE'
                END)
            ELSE POP.CALL_TO_ACTION
            END CALL_TO_ACTION
    FROM GTT_CAMP_SMS_POPULATION POP
    ;
    AP_PUBLIC.CORE_LOG_PKG.PEND;
    COMMIT;
    PSTATS('GTT_CAMP_SMS_POPULATION');

END IF;

<<FINISH_LINE>>
    
AP_PUBLIC.CORE_LOG_PKG.PFINISH ;
END;
/

