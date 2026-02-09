//
//  InitializeCollection.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/8/26.
//

import Supabase

func InitializeCollection(items: [ItemWrapper]) async {
//    do {
        let session = supabase.auth.currentUser?.id
        print(session ?? "")
        
//    } catch {
//        print(error)
//    }

}
