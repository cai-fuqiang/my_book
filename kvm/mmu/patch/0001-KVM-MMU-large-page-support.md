```diff
From 05da45583de9b383dc81dd695fe248431d6c9f2b Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <marcelo@kvack.org>
Date: Sat, 23 Feb 2008 11:44:30 -0300
Subject: [PATCH] KVM: MMU: large page support

Create large pages mappings if the guest PTE's are marked as such and
the underlying memory is hugetlbfs backed.  If the largepage contains
write-protected pages, a large pte is not used.

Gives a consistent 2% improvement for data copies on ram mounted
filesystem, without NPT/EPT.

Anthony measures a 4% improvement on 4-way kernbench, with NPT.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@qumranet.com>
---
 arch/x86/kvm/mmu.c         | 222 ++++++++++++++++++++++++++++++++-----
 arch/x86/kvm/paging_tmpl.h |  32 +++++-
 arch/x86/kvm/x86.c         |   1 +
 include/asm-x86/kvm_host.h |   9 ++
 include/linux/kvm_host.h   |   5 +
 virt/kvm/kvm_main.c        |  25 ++++-
 6 files changed, 262 insertions(+), 32 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 103d008dab8b..1932a3aeda1d 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -27,6 +27,7 @@
 #include <linux/highmem.h>
 #include <linux/module.h>
 #include <linux/swap.h>
+#include <linux/hugetlb.h>
 
 #include <asm/page.h>
 #include <asm/cmpxchg.h>
@@ -211,6 +212,11 @@ static int is_shadow_present_pte(u64 pte)
 		&& pte != shadow_notrap_nonpresent_pte;
 }
 
+static int is_large_pte(u64 pte)
+{
+	return pte & PT_PAGE_SIZE_MASK;
+}
+
 static int is_writeble_pte(unsigned long pte)
 {
 	return pte & PT_WRITABLE_MASK;
@@ -349,17 +355,101 @@ static void mmu_free_rmap_desc(struct kvm_rmap_desc *rd)
 	kfree(rd);
 }
 
+/*
+ * Return the pointer to the largepage write count for a given
+ * gfn, handling slots that are not large page aligned.
+ */
+static int *slot_largepage_idx(gfn_t gfn, struct kvm_memory_slot *slot)
+{
+	unsigned long idx;
+
+	idx = (gfn / KVM_PAGES_PER_HPAGE) -
+	      (slot->base_gfn / KVM_PAGES_PER_HPAGE);
+	return &slot->lpage_info[idx].write_count;
+}
+
+static void account_shadowed(struct kvm *kvm, gfn_t gfn)
+{
+	int *write_count;
+
+	write_count = slot_largepage_idx(gfn, gfn_to_memslot(kvm, gfn));
+	*write_count += 1;
+	WARN_ON(*write_count > KVM_PAGES_PER_HPAGE);
+}
+
+static void unaccount_shadowed(struct kvm *kvm, gfn_t gfn)
+{
+	int *write_count;
+
+	write_count = slot_largepage_idx(gfn, gfn_to_memslot(kvm, gfn));
+	*write_count -= 1;
+	WARN_ON(*write_count < 0);
+}
+
+static int has_wrprotected_page(struct kvm *kvm, gfn_t gfn)
+{
+	struct kvm_memory_slot *slot = gfn_to_memslot(kvm, gfn);
+	int *largepage_idx;
+
+	if (slot) {
+		largepage_idx = slot_largepage_idx(gfn, slot);
+		return *largepage_idx;
+	}
+
+	return 1;
+}
+
+static int host_largepage_backed(struct kvm *kvm, gfn_t gfn)
+{
+	struct vm_area_struct *vma;
+	unsigned long addr;
+
+	addr = gfn_to_hva(kvm, gfn);
+	if (kvm_is_error_hva(addr))
+		return 0;
+
+	vma = find_vma(current->mm, addr);
+	if (vma && is_vm_hugetlb_page(vma))
+		return 1;
+
+	return 0;
+}
+
+static int is_largepage_backed(struct kvm_vcpu *vcpu, gfn_t large_gfn)
+{
+	struct kvm_memory_slot *slot;
+
+	if (has_wrprotected_page(vcpu->kvm, large_gfn))
+		return 0;
+
+	if (!host_largepage_backed(vcpu->kvm, large_gfn))
+		return 0;
+
+	slot = gfn_to_memslot(vcpu->kvm, large_gfn);
+	if (slot && slot->dirty_bitmap)
+		return 0;
+
+	return 1;
+}
+
 /*
  * Take gfn and return the reverse mapping to it.
  * Note: gfn must be unaliased before this function get called
  */
 
-static unsigned long *gfn_to_rmap(struct kvm *kvm, gfn_t gfn)
+static unsigned long *gfn_to_rmap(struct kvm *kvm, gfn_t gfn, int lpage)
 {
 	struct kvm_memory_slot *slot;
+	unsigned long idx;
 
 	slot = gfn_to_memslot(kvm, gfn);
-	return &slot->rmap[gfn - slot->base_gfn];
+	if (!lpage)
+		return &slot->rmap[gfn - slot->base_gfn];
+
+	idx = (gfn / KVM_PAGES_PER_HPAGE) -
+	      (slot->base_gfn / KVM_PAGES_PER_HPAGE);
+
+	return &slot->lpage_info[idx].rmap_pde;
 }
 
 /*
@@ -371,7 +461,7 @@ static unsigned long *gfn_to_rmap(struct kvm *kvm, gfn_t gfn)
  * If rmapp bit zero is one, (then rmap & ~1) points to a struct kvm_rmap_desc
  * containing more mappings.
  */
-static void rmap_add(struct kvm_vcpu *vcpu, u64 *spte, gfn_t gfn)
+static void rmap_add(struct kvm_vcpu *vcpu, u64 *spte, gfn_t gfn, int lpage)
 {
 	struct kvm_mmu_page *sp;
 	struct kvm_rmap_desc *desc;
@@ -383,7 +473,7 @@ static void rmap_add(struct kvm_vcpu *vcpu, u64 *spte, gfn_t gfn)
 	gfn = unalias_gfn(vcpu->kvm, gfn);
 	sp = page_header(__pa(spte));
 	sp->gfns[spte - sp->spt] = gfn;
-	rmapp = gfn_to_rmap(vcpu->kvm, gfn);
+	rmapp = gfn_to_rmap(vcpu->kvm, gfn, lpage);
 	if (!*rmapp) {
 		rmap_printk("rmap_add: %p %llx 0->1\n", spte, *spte);
 		*rmapp = (unsigned long)spte;
@@ -449,7 +539,7 @@ static void rmap_remove(struct kvm *kvm, u64 *spte)
 		kvm_release_page_dirty(page);
 	else
 		kvm_release_page_clean(page);
-	rmapp = gfn_to_rmap(kvm, sp->gfns[spte - sp->spt]);
+	rmapp = gfn_to_rmap(kvm, sp->gfns[spte - sp->spt], is_large_pte(*spte));
 	if (!*rmapp) {
 		printk(KERN_ERR "rmap_remove: %p %llx 0->BUG\n", spte, *spte);
 		BUG();
@@ -515,7 +605,7 @@ static void rmap_write_protect(struct kvm *kvm, u64 gfn)
 	int write_protected = 0;
 
 	gfn = unalias_gfn(kvm, gfn);
-	rmapp = gfn_to_rmap(kvm, gfn);
+	rmapp = gfn_to_rmap(kvm, gfn, 0);
 
 	spte = rmap_next(kvm, rmapp, NULL);
 	while (spte) {
@@ -528,8 +618,27 @@ static void rmap_write_protect(struct kvm *kvm, u64 gfn)
 		}
 		spte = rmap_next(kvm, rmapp, spte);
 	}
+	/* check for huge page mappings */
+	rmapp = gfn_to_rmap(kvm, gfn, 1);
+	spte = rmap_next(kvm, rmapp, NULL);
+	while (spte) {
+		BUG_ON(!spte);
+		BUG_ON(!(*spte & PT_PRESENT_MASK));
+		BUG_ON((*spte & (PT_PAGE_SIZE_MASK|PT_PRESENT_MASK)) != (PT_PAGE_SIZE_MASK|PT_PRESENT_MASK));
+		pgprintk("rmap_write_protect(large): spte %p %llx %lld\n", spte, *spte, gfn);
+		if (is_writeble_pte(*spte)) {
+			rmap_remove(kvm, spte);
+			--kvm->stat.lpages;
+			set_shadow_pte(spte, shadow_trap_nonpresent_pte);
+			write_protected = 1;
+		}
+		spte = rmap_next(kvm, rmapp, spte);
+	}
+
 	if (write_protected)
 		kvm_flush_remote_tlbs(kvm);
+
+	account_shadowed(kvm, gfn);
 }
 
 #ifdef MMU_DEBUG
@@ -747,11 +856,17 @@ static void kvm_mmu_page_unlink_children(struct kvm *kvm,
 	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
 		ent = pt[i];
 
+		if (is_shadow_present_pte(ent)) {
+			if (!is_large_pte(ent)) {
+				ent &= PT64_BASE_ADDR_MASK;
+				mmu_page_remove_parent_pte(page_header(ent),
+							   &pt[i]);
+			} else {
+				--kvm->stat.lpages;
+				rmap_remove(kvm, &pt[i]);
+			}
+		}
 		pt[i] = shadow_trap_nonpresent_pte;
-		if (!is_shadow_present_pte(ent))
-			continue;
-		ent &= PT64_BASE_ADDR_MASK;
-		mmu_page_remove_parent_pte(page_header(ent), &pt[i]);
 	}
 	kvm_flush_remote_tlbs(kvm);
 }
@@ -791,6 +906,8 @@ static void kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
 	}
 	kvm_mmu_page_unlink_children(kvm, sp);
 	if (!sp->root_count) {
+		if (!sp->role.metaphysical)
+			unaccount_shadowed(kvm, sp->gfn);
 		hlist_del(&sp->hash_link);
 		kvm_mmu_free_page(kvm, sp);
 	} else {
@@ -894,7 +1011,8 @@ struct page *gva_to_page(struct kvm_vcpu *vcpu, gva_t gva)
 static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 			 unsigned pt_access, unsigned pte_access,
 			 int user_fault, int write_fault, int dirty,
-			 int *ptwrite, gfn_t gfn, struct page *page)
+			 int *ptwrite, int largepage, gfn_t gfn,
+			 struct page *page)
 {
 	u64 spte;
 	int was_rmapped = 0;
@@ -907,15 +1025,29 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		 write_fault, user_fault, gfn);
 
 	if (is_rmap_pte(*shadow_pte)) {
-		if (host_pfn != page_to_pfn(page)) {
+		/*
+		 * If we overwrite a PTE page pointer with a 2MB PMD, unlink
+		 * the parent of the now unreachable PTE.
+		 */
+		if (largepage && !is_large_pte(*shadow_pte)) {
+			struct kvm_mmu_page *child;
+			u64 pte = *shadow_pte;
+
+			child = page_header(pte & PT64_BASE_ADDR_MASK);
+			mmu_page_remove_parent_pte(child, shadow_pte);
+		} else if (host_pfn != page_to_pfn(page)) {
 			pgprintk("hfn old %lx new %lx\n",
 				 host_pfn, page_to_pfn(page));
 			rmap_remove(vcpu->kvm, shadow_pte);
+		} else {
+			if (largepage)
+				was_rmapped = is_large_pte(*shadow_pte);
+			else
+				was_rmapped = 1;
 		}
-		else
-			was_rmapped = 1;
 	}
 
+
 	/*
 	 * We don't set the accessed bit, since we sometimes want to see
 	 * whether the guest actually used the pte (in order to detect
@@ -930,6 +1062,8 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 	spte |= PT_PRESENT_MASK;
 	if (pte_access & ACC_USER_MASK)
 		spte |= PT_USER_MASK;
+	if (largepage)
+		spte |= PT_PAGE_SIZE_MASK;
 
 	spte |= page_to_phys(page);
 
@@ -944,7 +1078,8 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		}
 
 		shadow = kvm_mmu_lookup_page(vcpu->kvm, gfn);
-		if (shadow) {
+		if (shadow ||
+		   (largepage && has_wrprotected_page(vcpu->kvm, gfn))) {
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
 				 __FUNCTION__, gfn);
 			pte_access &= ~ACC_WRITE_MASK;
@@ -963,10 +1098,17 @@ unshadowed:
 		mark_page_dirty(vcpu->kvm, gfn);
 
 	pgprintk("%s: setting spte %llx\n", __FUNCTION__, spte);
+	pgprintk("instantiating %s PTE (%s) at %d (%llx) addr %llx\n",
+		 (spte&PT_PAGE_SIZE_MASK)? "2MB" : "4kB",
+		 (spte&PT_WRITABLE_MASK)?"RW":"R", gfn, spte, shadow_pte);
 	set_shadow_pte(shadow_pte, spte);
+	if (!was_rmapped && (spte & PT_PAGE_SIZE_MASK)
+	    && (spte & PT_PRESENT_MASK))
+		++vcpu->kvm->stat.lpages;
+
 	page_header_update_slot(vcpu->kvm, shadow_pte, gfn);
 	if (!was_rmapped) {
-		rmap_add(vcpu, shadow_pte, gfn);
+		rmap_add(vcpu, shadow_pte, gfn, largepage);
 		if (!is_rmap_pte(*shadow_pte))
 			kvm_release_page_clean(page);
 	} else {
@@ -984,7 +1126,8 @@ static void nonpaging_new_cr3(struct kvm_vcpu *vcpu)
 }
 
 static int __direct_map(struct kvm_vcpu *vcpu, gpa_t v, int write,
-			   gfn_t gfn, struct page *page, int level)
+			   int largepage, gfn_t gfn, struct page *page,
+			   int level)
 {
 	hpa_t table_addr = vcpu->arch.mmu.root_hpa;
 	int pt_write = 0;
@@ -998,7 +1141,13 @@ static int __direct_map(struct kvm_vcpu *vcpu, gpa_t v, int write,
 
 		if (level == 1) {
 			mmu_set_spte(vcpu, &table[index], ACC_ALL, ACC_ALL,
-				     0, write, 1, &pt_write, gfn, page);
+				     0, write, 1, &pt_write, 0, gfn, page);
+			return pt_write;
+		}
+
+		if (largepage && level == 2) {
+			mmu_set_spte(vcpu, &table[index], ACC_ALL, ACC_ALL,
+				    0, write, 1, &pt_write, 1, gfn, page);
 			return pt_write;
 		}
 
@@ -1027,12 +1176,18 @@ static int __direct_map(struct kvm_vcpu *vcpu, gpa_t v, int write,
 static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, int write, gfn_t gfn)
 {
 	int r;
+	int largepage = 0;
 
 	struct page *page;
 
 	down_read(&vcpu->kvm->slots_lock);
 
 	down_read(&current->mm->mmap_sem);
+	if (is_largepage_backed(vcpu, gfn & ~(KVM_PAGES_PER_HPAGE-1))) {
+		gfn &= ~(KVM_PAGES_PER_HPAGE-1);
+		largepage = 1;
+	}
+
 	page = gfn_to_page(vcpu->kvm, gfn);
 	up_read(&current->mm->mmap_sem);
 
@@ -1045,7 +1200,8 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, int write, gfn_t gfn)
 
 	spin_lock(&vcpu->kvm->mmu_lock);
 	kvm_mmu_free_some_pages(vcpu);
-	r = __direct_map(vcpu, v, write, gfn, page, PT32E_ROOT_LEVEL);
+	r = __direct_map(vcpu, v, write, largepage, gfn, page,
+			 PT32E_ROOT_LEVEL);
 	spin_unlock(&vcpu->kvm->mmu_lock);
 
 	up_read(&vcpu->kvm->slots_lock);
@@ -1180,6 +1336,8 @@ static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,
 {
 	struct page *page;
 	int r;
+	int largepage = 0;
+	gfn_t gfn = gpa >> PAGE_SHIFT;
 
 	ASSERT(vcpu);
 	ASSERT(VALID_PAGE(vcpu->arch.mmu.root_hpa));
@@ -1189,7 +1347,11 @@ static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,
 		return r;
 
 	down_read(&current->mm->mmap_sem);
-	page = gfn_to_page(vcpu->kvm, gpa >> PAGE_SHIFT);
+	if (is_largepage_backed(vcpu, gfn & ~(KVM_PAGES_PER_HPAGE-1))) {
+		gfn &= ~(KVM_PAGES_PER_HPAGE-1);
+		largepage = 1;
+	}
+	page = gfn_to_page(vcpu->kvm, gfn);
 	if (is_error_page(page)) {
 		kvm_release_page_clean(page);
 		up_read(&current->mm->mmap_sem);
@@ -1198,7 +1360,7 @@ static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,
 	spin_lock(&vcpu->kvm->mmu_lock);
 	kvm_mmu_free_some_pages(vcpu);
 	r = __direct_map(vcpu, gpa, error_code & PFERR_WRITE_MASK,
-			 gpa >> PAGE_SHIFT, page, TDP_ROOT_LEVEL);
+			 largepage, gfn, page, TDP_ROOT_LEVEL);
 	spin_unlock(&vcpu->kvm->mmu_lock);
 	up_read(&current->mm->mmap_sem);
 
@@ -1397,7 +1559,8 @@ static void mmu_pte_write_zap_pte(struct kvm_vcpu *vcpu,
 
 	pte = *spte;
 	if (is_shadow_present_pte(pte)) {
-		if (sp->role.level == PT_PAGE_TABLE_LEVEL)
+		if (sp->role.level == PT_PAGE_TABLE_LEVEL ||
+		    is_large_pte(pte))
 			rmap_remove(vcpu->kvm, spte);
 		else {
 			child = page_header(pte & PT64_BASE_ADDR_MASK);
@@ -1405,6 +1568,8 @@ static void mmu_pte_write_zap_pte(struct kvm_vcpu *vcpu,
 		}
 	}
 	set_shadow_pte(spte, shadow_trap_nonpresent_pte);
+	if (is_large_pte(pte))
+		--vcpu->kvm->stat.lpages;
 }
 
 static void mmu_pte_write_new_pte(struct kvm_vcpu *vcpu,
@@ -1412,7 +1577,8 @@ static void mmu_pte_write_new_pte(struct kvm_vcpu *vcpu,
 				  u64 *spte,
 				  const void *new)
 {
-	if (sp->role.level != PT_PAGE_TABLE_LEVEL) {
+	if ((sp->role.level != PT_PAGE_TABLE_LEVEL)
+	    && !vcpu->arch.update_pte.largepage) {
 		++vcpu->kvm->stat.mmu_pde_zapped;
 		return;
 	}
@@ -1460,6 +1626,8 @@ static void mmu_guess_page_from_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 	u64 gpte = 0;
 	struct page *page;
 
+	vcpu->arch.update_pte.largepage = 0;
+
 	if (bytes != 4 && bytes != 8)
 		return;
 
@@ -1487,9 +1655,13 @@ static void mmu_guess_page_from_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 		return;
 	gfn = (gpte & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
 
-	down_read(&vcpu->kvm->slots_lock);
+	down_read(&current->mm->mmap_sem);
+	if (is_large_pte(gpte) && is_largepage_backed(vcpu, gfn)) {
+		gfn &= ~(KVM_PAGES_PER_HPAGE-1);
+		vcpu->arch.update_pte.largepage = 1;
+	}
 	page = gfn_to_page(vcpu->kvm, gfn);
-	up_read(&vcpu->kvm->slots_lock);
+	up_read(&current->mm->mmap_sem);
 
 	if (is_error_page(page)) {
 		kvm_release_page_clean(page);
diff --git a/arch/x86/kvm/paging_tmpl.h b/arch/x86/kvm/paging_tmpl.h
index 4b55f462e2b3..17f9d160ca34 100644
--- a/arch/x86/kvm/paging_tmpl.h
+++ b/arch/x86/kvm/paging_tmpl.h
@@ -248,6 +248,7 @@ static void FNAME(update_pte)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *page,
 	pt_element_t gpte;
 	unsigned pte_access;
 	struct page *npage;
+	int largepage = vcpu->arch.update_pte.largepage;
 
 	gpte = *(const pt_element_t *)pte;
 	if (~gpte & (PT_PRESENT_MASK | PT_ACCESSED_MASK)) {
@@ -264,7 +265,8 @@ static void FNAME(update_pte)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *page,
 		return;
 	get_page(npage);
 	mmu_set_spte(vcpu, spte, page->role.access, pte_access, 0, 0,
-		     gpte & PT_DIRTY_MASK, NULL, gpte_to_gfn(gpte), npage);
+		     gpte & PT_DIRTY_MASK, NULL, largepage, gpte_to_gfn(gpte),
+		     npage);
 }
 
 /*
@@ -272,8 +274,8 @@ static void FNAME(update_pte)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *page,
  */
 static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 			 struct guest_walker *walker,
-			 int user_fault, int write_fault, int *ptwrite,
-			 struct page *page)
+			 int user_fault, int write_fault, int largepage,
+			 int *ptwrite, struct page *page)
 {
 	hpa_t shadow_addr;
 	int level;
@@ -301,11 +303,19 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 		shadow_ent = ((u64 *)__va(shadow_addr)) + index;
 		if (level == PT_PAGE_TABLE_LEVEL)
 			break;
-		if (is_shadow_present_pte(*shadow_ent)) {
+
+		if (largepage && level == PT_DIRECTORY_LEVEL)
+			break;
+
+		if (is_shadow_present_pte(*shadow_ent)
+		    && !is_large_pte(*shadow_ent)) {
 			shadow_addr = *shadow_ent & PT64_BASE_ADDR_MASK;
 			continue;
 		}
 
+		if (is_large_pte(*shadow_ent))
+			rmap_remove(vcpu->kvm, shadow_ent);
+
 		if (level - 1 == PT_PAGE_TABLE_LEVEL
 		    && walker->level == PT_DIRECTORY_LEVEL) {
 			metaphysical = 1;
@@ -339,7 +349,7 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 	mmu_set_spte(vcpu, shadow_ent, access, walker->pte_access & access,
 		     user_fault, write_fault,
 		     walker->ptes[walker->level-1] & PT_DIRTY_MASK,
-		     ptwrite, walker->gfn, page);
+		     ptwrite, largepage, walker->gfn, page);
 
 	return shadow_ent;
 }
@@ -369,6 +379,7 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	int write_pt = 0;
 	int r;
 	struct page *page;
+	int largepage = 0;
 
 	pgprintk("%s: addr %lx err %x\n", __FUNCTION__, addr, error_code);
 	kvm_mmu_audit(vcpu, "pre page fault");
@@ -396,6 +407,14 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	}
 
 	down_read(&current->mm->mmap_sem);
+	if (walker.level == PT_DIRECTORY_LEVEL) {
+		gfn_t large_gfn;
+		large_gfn = walker.gfn & ~(KVM_PAGES_PER_HPAGE-1);
+		if (is_largepage_backed(vcpu, large_gfn)) {
+			walker.gfn = large_gfn;
+			largepage = 1;
+		}
+	}
 	page = gfn_to_page(vcpu->kvm, walker.gfn);
 	up_read(&current->mm->mmap_sem);
 
@@ -410,7 +429,8 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	spin_lock(&vcpu->kvm->mmu_lock);
 	kvm_mmu_free_some_pages(vcpu);
 	shadow_pte = FNAME(fetch)(vcpu, addr, &walker, user_fault, write_fault,
-				  &write_pt, page);
+				  largepage, &write_pt, page);
+
 	pgprintk("%s: shadow pte %p %llx ptwrite %d\n", __FUNCTION__,
 		 shadow_pte, *shadow_pte, write_pt);
 
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index e8e64927bddc..0458bd516185 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -88,6 +88,7 @@ struct kvm_stats_debugfs_item debugfs_entries[] = {
 	{ "mmu_recycled", VM_STAT(mmu_recycled) },
 	{ "mmu_cache_miss", VM_STAT(mmu_cache_miss) },
 	{ "remote_tlb_flush", VM_STAT(remote_tlb_flush) },
+	{ "largepages", VM_STAT(lpages) },
 	{ NULL }
 };
 
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 8c3f74b73524..95473ef5a906 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -39,6 +39,13 @@
 #define INVALID_PAGE (~(hpa_t)0)
 #define UNMAPPED_GVA (~(gpa_t)0)
 
+/* shadow tables are PAE even on non-PAE hosts */
+#define KVM_HPAGE_SHIFT 21
+#define KVM_HPAGE_SIZE (1UL << KVM_HPAGE_SHIFT)
+#define KVM_HPAGE_MASK (~(KVM_HPAGE_SIZE - 1))
+
+#define KVM_PAGES_PER_HPAGE (KVM_HPAGE_SIZE / PAGE_SIZE)
+
 #define DE_VECTOR 0
 #define UD_VECTOR 6
 #define NM_VECTOR 7
@@ -230,6 +237,7 @@ struct kvm_vcpu_arch {
 	struct {
 		gfn_t gfn;          /* presumed gfn during guest pte update */
 		struct page *page;  /* page corresponding to that gfn */
+		int largepage;
 	} update_pte;
 
 	struct i387_fxsave_struct host_fx_image;
@@ -307,6 +315,7 @@ struct kvm_vm_stat {
 	u32 mmu_recycled;
 	u32 mmu_cache_miss;
 	u32 remote_tlb_flush;
+	u32 lpages;
 };
 
 struct kvm_vcpu_stat {
diff --git a/include/linux/kvm_host.h b/include/linux/kvm_host.h
index 994278fb5883..9750bb3c5a75 100644
--- a/include/linux/kvm_host.h
+++ b/include/linux/kvm_host.h
@@ -103,6 +103,10 @@ struct kvm_memory_slot {
 	unsigned long flags;
 	unsigned long *rmap;
 	unsigned long *dirty_bitmap;
+	struct {
+		unsigned long rmap_pde;
+		int write_count;
+	} *lpage_info;
 	unsigned long userspace_addr;
 	int user_alloc;
 };
@@ -169,6 +173,7 @@ int kvm_arch_set_memory_region(struct kvm *kvm,
 				int user_alloc);
 gfn_t unalias_gfn(struct kvm *kvm, gfn_t gfn);
 struct page *gfn_to_page(struct kvm *kvm, gfn_t gfn);
+unsigned long gfn_to_hva(struct kvm *kvm, gfn_t gfn);
 void kvm_release_page_clean(struct page *page);
 void kvm_release_page_dirty(struct page *page);
 int kvm_read_guest_page(struct kvm *kvm, gfn_t gfn, void *data, int offset,
diff --git a/virt/kvm/kvm_main.c b/virt/kvm/kvm_main.c
index c41eb57ce29b..31db9b4d3016 100644
--- a/virt/kvm/kvm_main.c
+++ b/virt/kvm/kvm_main.c
@@ -212,9 +212,13 @@ static void kvm_free_physmem_slot(struct kvm_memory_slot *free,
 	if (!dont || free->dirty_bitmap != dont->dirty_bitmap)
 		vfree(free->dirty_bitmap);
 
+	if (!dont || free->lpage_info != dont->lpage_info)
+		vfree(free->lpage_info);
+
 	free->npages = 0;
 	free->dirty_bitmap = NULL;
 	free->rmap = NULL;
+	free->lpage_info = NULL;
 }
 
 void kvm_free_physmem(struct kvm *kvm)
@@ -324,6 +328,25 @@ int __kvm_set_memory_region(struct kvm *kvm,
 		new.user_alloc = user_alloc;
 		new.userspace_addr = mem->userspace_addr;
 	}
+	if (npages && !new.lpage_info) {
+		int largepages = npages / KVM_PAGES_PER_HPAGE;
+		if (npages % KVM_PAGES_PER_HPAGE)
+			largepages++;
+		if (base_gfn % KVM_PAGES_PER_HPAGE)
+			largepages++;
+
+		new.lpage_info = vmalloc(largepages * sizeof(*new.lpage_info));
+
+		if (!new.lpage_info)
+			goto out_free;
+
+		memset(new.lpage_info, 0, largepages * sizeof(*new.lpage_info));
+
+		if (base_gfn % KVM_PAGES_PER_HPAGE)
+			new.lpage_info[0].write_count = 1;
+		if ((base_gfn+npages) % KVM_PAGES_PER_HPAGE)
+			new.lpage_info[largepages-1].write_count = 1;
+	}
 
 	/* Allocate page dirty bitmap if needed */
 	if ((new.flags & KVM_MEM_LOG_DIRTY_PAGES) && !new.dirty_bitmap) {
@@ -467,7 +490,7 @@ int kvm_is_visible_gfn(struct kvm *kvm, gfn_t gfn)
 }
 EXPORT_SYMBOL_GPL(kvm_is_visible_gfn);
 
-static unsigned long gfn_to_hva(struct kvm *kvm, gfn_t gfn)
+unsigned long gfn_to_hva(struct kvm *kvm, gfn_t gfn)
 {
 	struct kvm_memory_slot *slot;
 
-- 
2.41.0
```
