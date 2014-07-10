/*
* Acts as the base class for different classes New AccountOverride Ext, Edit contact, Lead Conversion
* Contains common functionalities
*/
public without sharing virtual class  BaseExtension {
  public list<SelectOption> lstOpptyRecordType{get;set;}
  public Lead currentLead{get;set;}
  
  public String selectedOpptyType{get;set;}
  public String OpptyTypeName{get;set;}
  public Integer step{get;set;}
  public string createOpptyText{get;set;} 
  public Boolean isCreateOppty{get;set;}
  public Boolean isAddress1Required{get;set;} 
  public string emailORPhoneText{get;set;}
  public Opportunity convertedOppty{get;set;}
  
  public list<SelectOption> lstConvertedLeadStatuses{get;set;}
  public string defaultConvertedStatus{get;set;}
  static Map<String,Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap(); 
  static Map<String,Schema.SObjectField> contactFieldMap = Schema.SObjectType.Contact.fields.getMap();
  static transient Map<String, Schema.SObjectType> mapGlobalDescribe = Schema.getGlobalDescribe();  
  static boolean isOSPUser = JDSU_Configuration__c.getInstance().OSP_User__c; 
  
  public Map<String,FieldSet_Config__c> mapFieldSetConfig = new Map<String,FieldSet_Config__c>();
  
    
    public BaseExtension() {
      fetchOpptyRecordTypes();
      step = 0;
      isCreateOppty = true;
      createOpptyText = 'Do you wish to create an Opportunity as part of converting this lead?<br/> If so, please check the Create Opportunity box and select the Type of Opportunity to create.';
      emailORPhoneText = '<font color="blue">Please ensure you provide at least a phone number OR an email address when creating a Contact</font>';
      convertedOppty = new Opportunity();    
    }
    
   /*
   *
   *Method to convert the lead
   */
   public PageReference doLeadConvert(Id contactIdToSet,Id accountIdToSet, Boolean opptyCreate,Lead clead) {
    
    Database.LeadConvertResult lcr;
    Savepoint sp = Database.setSavepoint();
    clead = [SELECT Id,Name,Industry,End_User__c,Lastname,Company,Country,Email,RecordTypeId,RecordType.Name,Phone,Phone__c,
            FirstName,Street,City,State,PostalCode,OwnerId,Title,End_Customer__c 
            FROM LEAD 
            WHERE Id = :clead.Id];
    try {
      if(String.valueOf(clead.OwnerId).startsWith('00G')) {
        clead.OwnerId = UserInfo.getUserId();
      } 
      clead.Kill_Pending_WFR__c = true;
      update clead;

      Database.LeadConvert leadConvert = new database.LeadConvert();
      leadConvert.setLeadId(clead.id);
      leadConvert.setAccountId(accountIdToSet);
      leadConvert.setContactId(contactIdToSet);
      
      leadConvert.setDoNotCreateOpportunity(!opptyCreate);
      if(opptyCreate) {
        leadConvert.setOpportunityName(clead.Company);
      }
      leadConvert.setSendNotificationEmail(false);
      leadConvert.setConvertedStatus(defaultConvertedStatus);
      byPassOpportunityValidation();
      lcr = Database.convertLead(leadConvert);   
      if(opptyCreate) {
        updateOppty(lcr,cLead);
         /**
          * Redirecting Opportunity to detail page layout, not an edit page.
         **/
        //return new PageReference('/' + lcr.getOpportunityId() + '/e?retURL=/'+lcr.getOpportunityId());
        return new PageReference('/' + lcr.getOpportunityId() );        
      }
            
    }
    catch(DmlException e) {       
      //ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,e.getDMLMessage(0)));
      ApexPages.addMessages(e);
      Database.rollback(sp);
      return null;
    }        
    return new PageReference('/' + lcr.getAccountId());
  }
  
  public void byPassOpportunityValidation() {
    OpportunityManagement.skipValidation = true;
  }
  
  /*
  *
  *To update opportunity after lead is converted
  *
  */
  private void updateOppty(Database.LeadConvertResult lcr,Lead clead) {
    Opportunity oppty = new Opportunity(Id = lcr.getOpportunityId(),RecordTypeId = selectedOpptyType,OwnerId = cLead.OwnerId); 
    if(convertedOppty.OwnerId != null) {
      oppty.OwnerId = convertedOppty.OwnerId; 
    }   
    if(clead.RecordType.name == 'Deal Registration') {
      oppty.Lead_Name__c = clead.Name;    
      oppty.Lead_Email__c = clead.Email;
      oppty.Lead_Phone__c = clead.phone;
      //oppty.Next_Steps__c = opportunity.Next_Steps__c;
      oppty.Lead_Phone__c = clead.phone;
      oppty.Lead_Street__c= clead.Street;
      oppty.Lead_City__c= clead.city;
      oppty.Lead_State_Province__c= clead.State;
      oppty.Lead_Country__c= clead.Country;
      oppty.Lead_Zip_Postal_Code__c= clead.PostalCode;    
      oppty.Lead_Title__c = clead.title; 
      //oppty.CurrencyIsoCode = user.CurrencyIsoCode;
      //oppty.AccountId = user.AccountId; 
      oppty.StageName = 'T0-Converted Lead/Identified Opportunity';     
      //oppty.Ownerid = user.Id;
      if(lead.End_Customer__c != null) {
        oppty.End_Customer__c = clead.End_Customer__c;
      }
      else {
        oppty.End_Customer__c = clead.company;
      }
      oppty.Account_Type__c = 'Title taking partner (distributor, or other)';
    }  
     /*
    I-52227 : End User field population for Oppty and Lead Convert - 36
    */
    if(clead.End_User__c != null) {
      oppty.End_User__c = clead.End_User__c;
    }
    else {
      oppty.End_User__c = lcr.getAccountId();
    }
      
    oppty.Industry__c = clead.Industry;
    update oppty;   
    List<Contact> lstContact = [Select Id,Role__c from Contact where Id = :lcr.getContactId()];
    List<OpportunityContactRole> lstOpptyContactRole = [Select Id,ContactId,OpportunityId from OpportunityContactRole where OpportunityId = :lcr.getOpportunityId() AND ContactId = :lstContact[0].Id];
    if(!lstOpptyContactRole.isEmpty()) {
      lstOpptyContactRole[0].Role = lstContact[0].Role__c;
      lstOpptyContactRole[0].isPrimary = true;
      update lstOpptyContactRole;
      return;
    }
    if(!lstContact.isEmpty()) { 
      OpportunityContactRole cRole = new OpportunityContactRole(OpportunityId = lcr.getOpportunityId(),ContactId = lstContact[0].Id,Role = lstContact[0].Role__c,isPrimary = true);
      insert cRole;
    }       
  }
  
  /*
  *
  *populate default oppty owner from Account
  */
  
  public void populateDefaultOpportunityOwner(Id accountId) {
    List<Account> lstAccount = [Select Id,OwnerId from Account where Id = :accountId];
    if(lstAccount.isEmpty()) {
      convertedOppty.OwnerId = UserInfo.getUserId();
      return;
    }
    convertedOppty.OwnerId = lstAccount[0].OwnerId; 
  }
  
  /*
  *
  *To fetch converted lead statuses depending on leads recordtype and business process applicable
  */
  public void fetchConvertedStatuses() {
    lstConvertedLeadStatuses = new list<SelectOption>();    
    List<RecordType> lstRecordType = [Select Id,BusinessProcessId from RecordType WHERE Id = :currentLead.RecordTypeId];
    if(lstRecordType.isEmpty()) {
      return;
    }
    List<BusinessProcess> lstBusinessProcess = [Select Id,Name from BusinessProcess WHERE Id = :lstRecordType[0].BusinessProcessId];
    if(lstBusinessProcess.isEmpty()) {
      return;
    }
    String processName = lstBusinessProcess[0].Name;
    for(Lead_Process_Status_Map__c processes : Lead_Process_Status_Map__c.getAll().values()) {
      if(processes.Process_Name__c == processName) {
        lstConvertedLeadStatuses.add(new SelectOption(processes.Status__c,processes.Status__c));
        defaultConvertedStatus = processes.Status__c;
      }
    }
  }
  /*
  *
  *To fetch all opportunity recordtype accessible to current user
  */
   private void fetchOpptyRecordTypes() {
    lstOpptyRecordType = new list<SelectOption>();
    Schema.DescribeSObjectResult describe = Schema.SObjectType.Opportunity; 
    Map<Id,Schema.RecordTypeInfo> rtMapById = describe.getRecordTypeInfosById();
    map<String,String> mpRecordTypes = new map<String,String>(); 
    list<String> lstRTypeNames = new list<String>(); 
    for(Id rTypeId : rtMapById.keySet()) {        
      RecordTypeInfo rTypeinfo = rtMapById.get(rTypeId);
      if(rTypeinfo.Name == 'Master' || !rTypeinfo.isAvailable()) {
        continue;
      } 
      if(rTypeinfo.isDefaultRecordTypeMapping()) {
        selectedOpptyType = rTypeId; 
        OpptyTypeName = rTypeinfo.Name; 
      }
      lstRTypeNames.add(rTypeinfo.Name);
      mpRecordTypes.put(rTypeinfo.Name,rTypeId);
    }
    lstRTypeNames.sort();
    for(String rName : lstRTypeNames) {
      lstOpptyRecordType.add(new SelectOption(mpRecordTypes.get(rName),rName));
    }
  }
  
  public void getFieldSetConfig(){
    for(FieldSet_Config__c FieldSetConfig: FieldSet_Config__c.getAll().values()){
      String key = FieldSetConfig.Object_Name__c + '~' + FieldSetConfig.Section_Name__c ;
      if(FieldSetConfig.Record_Type__c != null){
        mapFieldSetConfig.put(key.toLowerCase() + '~' + FieldSetConfig.Record_Type__c.toLowerCase(), FieldSetConfig); 
      }
      if(FieldSetConfig.IsOSP__c){
        key += 'osp';
      }
      mapFieldSetConfig.put(key.toLowerCase(), FieldSetConfig);
    }
  }
  
  public string getFieldSets(String ObjectName,String SectionName, Lead lead){
     FieldSet_Config__c fieldSetConfig;
     String key = ObjectName.toLowerCase() + '~' + SectionName.toLowerCase();
     
     if(mapFieldSetConfig.containsKey(key)){
       fieldSetConfig = mapFieldSetConfig.get(key); 
     }
     
     if(isOSPUser && mapFieldSetConfig.containsKey(key + 'osp')){
        fieldSetConfig = mapFieldSetConfig.get(key + 'osp');
     }
     
     if(lead != null && lead.RecordTypeId != null){ 
       if(mapFieldSetConfig.containsKey(key + '~' + lead.RecordType.Name.toLowerCase())){
         fieldSetConfig = mapFieldSetConfig.get(key + '~' + lead.RecordType.Name.toLowerCase());
       }
     }
     return fieldSetConfig.FieldSets__c; 
  }
  
  public void isAddressMandatory() {
    for( Schema.FieldSetMember fieldSetmember : SObjectType.Account.FieldSets.Account_Detail_Left.getFields()) {
      if(fieldSetmember.getFieldPath() == 'Address_1__c') {
        isAddress1Required = fieldSetmember.getRequired() || fieldSetmember.getDBRequired(); 
      }
    }
  }
  
  //
  // Class to wrap field sets for different sections
  //
  public class FieldSetWrapper {
    public Schema.FieldSetMember fieldSetMember {get;set;}
    public FieldSetWrapper(Schema.FieldSetMember fieldSet) {
      this.fieldSetMember = fieldSet;
    }
    public FieldSetWrapper() {
      
    }
    public Boolean getIsNull() {
      return (this.fieldSetMember == null);
    }
    
    //=====================================================//
    //Generate Field Wrapper objects combining lists
    //====================================================//
      public List<FieldSetWrapper> generateFieldSetWrapper(String objectName, String fieldSets){
        
        List<List<Schema.FieldSetMember>> lstAllFieldSetMembers = new List<List<Schema.FieldSetMember>>(); 
        Integer size = 0;
        
        for(String fieldSetName : fieldSets.split(',')){
           List<Schema.FieldSetMember> lstFieldSetWrapper = mapGlobalDescribe.get(objectName.trim()).getDescribe().FieldSets.getMap().get(fieldSetName.trim()).getFields();
            
           lstAllFieldSetMembers.add(lstFieldSetWrapper);
           if(size < lstFieldSetWrapper.size()){
            size = lstFieldSetWrapper.size();
           }
        }
        
        List<FieldSetWrapper> lstMasterList = new List<FieldSetWrapper>();
        for(Integer i = 0;i < size; i++) {
          for(List<Schema.FieldSetMember> listFieldSetWrapper : lstAllFieldSetMembers){
            lstMasterList.add(new FieldSetWrapper(i < listFieldSetWrapper.size() ? listFieldSetWrapper[i]:null));
          }
        }
       return lstMasterList;
      }
  }
}