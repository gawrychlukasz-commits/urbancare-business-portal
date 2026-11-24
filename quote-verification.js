
let verifyingQuoteId=null;
function openQuoteVerification(id){
 const q=quoteRecords.find(x=>x.id===id);
 if(!q||q.is_verified!==false)return;
 verifyingQuoteId=id;
 const d=q.quote_data||{}, c=clientRecords.find(x=>x.id===q.client_id);
 const lines=['BPL internal reference: '+(q.quote_number||'NUMBER NOT CONFIRMED'),
 'Number printed on client PDF: '+(q.original_quote_number||q.quote_number||'NOT CONFIRMED'),
 'Client: '+(c?.business_name||'UNKNOWN'),
 'Quote date: '+(d.qDate||'UNKNOWN'),
 'Service: '+(d.qTitle||'Not provided'),
 'Scope: '+(d.qScope||'Not provided'),
 d.qOption1?'Option 1: '+d.qOption1+' $'+d.qPrice1:'',
 d.qOption2?'Option 2: '+d.qOption2+' $'+d.qPrice2:'',
 !d.qOption1&&!d.qOption2?'Amount: $'+(d.qCustomTotal||'not recorded'):'',
 'Status: '+q.status.toUpperCase()+' (not proof of client acceptance)',
 'Delivery: '+(q.delivery_method||'Unknown')+' / '+(q.sent_date||'Date not confirmed'),
 'Original PDF: '+(q.original_pdf_path?'SAVED':'NOT YET SAVED'),
 d.sourceQuoteNote&&!(q.original_quote_number&&d.importKey==='cove-walkway-2026-11-23')?'Notes: '+d.sourceQuoteNote:''].filter(Boolean);
 $('qVerifyDetails').textContent=lines.join('\n');
 $('qVerifyPdf').value='';$('qVerifyPdf').disabled=Boolean(q.original_pdf_path);
 $('qVerifyConfirm').textContent=q.original_pdf_path?'VERIFY quote':'Upload original PDF & VERIFY';
 $('qVerifyStatus').textContent='Compare these details with the original PDF; verification does not mean customer acceptance.';
 $('quoteVerifyPanel').classList.remove('hide');
 $('quoteVerifyPanel').scrollIntoView({behavior:'smooth',block:'start'});
}
$('qVerifyCancel').onclick=()=>{
 verifyingQuoteId=null;$('qVerifyPdf').value='';$('quoteVerifyPanel').classList.add('hide');
};
$('qVerifyConfirm').onclick=async()=>{
 const q=quoteRecords.find(x=>x.id===verifyingQuoteId);
 if(!q||q.is_verified!==false||!sb||!authUser)return;
 if(!q.quote_number){$('qVerifyStatus').textContent='Quote number is unconfirmed. Correct the imported record before verification.';return;}
 const file=$('qVerifyPdf').files[0];
 if(!q.original_pdf_path&&(!file||file.size===0||file.size>10485760||!(file.type==='application/pdf'||/\.pdf$/i.test(file.name)))){
  $('qVerifyStatus').textContent='Select the original PDF (up to 10 MB).';return;
 }
 if(!confirm('Confirm the PDF is numbered '+(q.original_quote_number||q.quote_number)+
    ' and matches BPL reference '+q.quote_number+' and the listed details? This does not record customer acceptance.'))return;
 const btn=$('qVerifyConfirm');btn.disabled=true;
 try{
  if(!q.original_pdf_path){
   const path=authUser.id+'/'+q.id+'.pdf';
   $('qVerifyStatus').textContent='Uploading original PDF to private storage…';
   const {error:uploadError}=await sb.storage.from('quote-pdfs').upload(path,file,{contentType:'application/pdf',upsert:false});
   if(uploadError){
    if(!String(uploadError.message||'').toLowerCase().includes('already exists'))throw uploadError;
    const {data:list,error:listError}=await sb.storage.from('quote-pdfs').list(authUser.id,{search:q.id+'.pdf'});
    if(listError||!list?.some(x=>x.name===q.id+'.pdf'))throw uploadError;
   }
   const {error:attachError}=await sb.rpc('attach_original_quote_pdf',{p_quote_id:q.id,p_path:path});
   if(attachError)throw attachError;
  }
  const {data,error}=await sb.from('quotes').update({is_verified:true,updated_at:new Date().toISOString()}).eq('id',q.id).eq('is_verified',false).select('id,is_verified,original_pdf_path').single();
  if(error)throw error;
  if(data?.is_verified!==true||!data.original_pdf_path)throw new Error('Supabase did not confirm PDF and verification.');
  await loadQuotes();
  if(!quoteRecords.some(x=>x.id===q.id&&x.is_verified===true&&x.original_pdf_path))throw new Error('Verification did not refresh.');
  $('quoteVerifyPanel').classList.add('hide');verifyingQuoteId=null;$('qVerifyPdf').value='';
  $('quotesStatus').textContent='Quote '+q.quote_number+' VERIFIED with PDF. '+$('quotesStatus').textContent;
 }catch(e){$('qVerifyStatus').textContent='Not verified: '+(e.message||'Unknown error')+'. Do not create a duplicate quote.';}
 finally{btn.disabled=false;}
};
