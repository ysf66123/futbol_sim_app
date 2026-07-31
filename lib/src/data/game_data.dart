const Map<String, dynamic> defaultGameConfig = {
  'max_turns': 21,
  'match_turns': [7, 14, 21],
  'augment_turns': [1, 3, 6],
  'turn_time_seconds': 60,
  'shop_pool_size': 4,
  'income_amount': 175,
  'risk_success_amount': 300,
  'risk_failure_amount': 50,
  'shop_probabilities': {
    'tier1_0_70': 40,
    'tier2_70_80': 30,
    'tier3_80_85': 20,
    'tier4_85_90': 10,
  },
};

const List<String> playerList = ['oyuncu_1', 'oyuncu_2'];

final Map<String, Map<String, dynamic>> augments = {
  'VALVERDE_BONUS': {
    'name': 'Yıldız Takviyesi (Valverde)',
    'description':
        'Hemen Orta Saha oyuncusu Valverde\'yi takıma kat. Valverde, havuzdan kalıcı olarak çıkarılır.',
    'type': 'player_reward',
    'details': {'player_id': 'valverde_01'},
  },
  'GOLD_250': {
    'name': 'Ekonomik Refah',
    'description': 'Anında 250 Altın kazanırsın.',
    'type': 'gold_reward',
    'details': {'amount': 250},
  },
  'RANDOM_PLAYER_50G': {
    'name': 'Gizli Yetenek Avı',
    'description': 'Rastgele bir sahipsiz oyuncu ve 50 Altın kazanırsın.',
    'type': 'gold_and_random_player',
    'details': {'gold': 50},
  },
  'STEAL_PLAYER': {
    'name': 'Oyuncu Transferi',
    'description':
        'Rakibinin takımından rastgele bir oyuncu sana transfer olur.',
    'type': 'steal_player',
  },
  'SARA_DISCOUNT': {
    'name': 'Özel İndirim',
    'description':
        'Orta Saha oyuncusu Sara veya Forvet oyuncusu Yunus, mağazana gelirse onları %50 indirimle satın alabilirsin.',
    'type': 'player_discount',
    'details': {
      'player_ids': ['sara_01', 'yunus_01'],
      'discount_percent': 0.5,
    },
  },
  'RISKY_INCOME': {
    'name': 'Finansal Kumar (Gecikmeli)',
    'description':
        'Mevcut tüm Altınını kaybedersin. Ancak 6. Turun başında kaybettiğin paranın 2 katını geri alırsın.',
    'type': 'delayed_gold_loss',
    'details': {'turn': 6},
  },
  'BETTER_SALE': {
    'name': 'Yüksek Likidite',
    'description':
        'Oyuncuları sattığında satış fiyatı %50 yerine %75 olarak hesaplanır.',
    'type': 'persistent_multiplier',
    'details': {'sale_multiplier': 0.75},
  },
  'RISK_BOOST': {
    'name': 'Risk İştahı',
    'description':
        'Risk Al butonundaki 300 Altın kazanma şansı %25\'ten %35\'e yükselir.',
    'type': 'persistent_multiplier',
    'details': {'risk_chance': 0.35},
  },
  'ATTACK_BUFF': {
    'name': 'Hücum Güçlendirmesi',
    'description':
        'Elindeki tüm oyuncuların Şut, Pas ve Hücum özellikleri kalıcı olarak +10 artırılır.',
    'type': 'stat_boost',
    'details': {
      'stats': ['sut', 'pas', 'hucum'],
      'amount': 10,
    },
  },
  'LOW_RATING_PLAYER_150G': {
    'name': 'Kadronun Derinliği',
    'description':
        '150 Altın ve 70 Reytingin altında rastgele bir sahipsiz oyuncu kazanırsın.',
    'type': 'gold_and_random_low_rating_player',
    'details': {'gold': 150, 'rating_limit': 70},
  },
  'MARKET_SABOTAGE': {
    'name': 'Pazar Sabotajı',
    'description':
        'Bu eklenti seçildiğinde rakibin mağazasına 10. tura kadar gelen tüm oyuncuların fiyatı 40 Altın artar.',
    'type': 'opponent_debuff',
    'details': {
      'debuff_type': 'shop_price_increase',
      'value': {'amount': 40, 'until_turn': 10},
    },
  },
  'GOALKEEPER_AMBARGO': {
    'name': 'Kaleci Ambargosu',
    'description':
        '10. tura kadar rakibin mağazasına Kaleci mevkiinde oyuncu gelmez.',
    'type': 'opponent_debuff',
    'details': {'debuff_type': 'no_goalkeepers_until', 'value': 10},
  },
  'FORM_DROP': {
    'name': 'Form Düşüşü',
    'description':
        'Rakibinin takımından rastgele bir oyuncunun tüm özellikleri ve reytingi kalıcı olarak -5 düşer.',
    'type': 'opponent_player_debuff',
    'details': {'amount': -5},
  },
  'PASSIVE_INCOME': {
    'name': 'Yatırım Getirisi',
    'description':
        'Her çift sayılı turun sonunda pasif olarak 25 ile 50 arasında rastgele Altın kazanırsın.',
    'type': 'persistent_passive_effect',
    'details': {'effect_type': 'passive_gold'},
  },
  'HEAD_START': {
    'name': 'Maça Önde Başla',
    'description':
        'Eklentiyi seçtikten sonraki İLK MAÇA doğrudan 1-0 önde başlarsın.',
    'type': 'persistent_match_effect',
    'details': {'effect_type': 'head_start_goal'},
  },
  'FINANCIAL_PRESSURE': {
    'name': 'Finansal Baskı',
    'description':
        'Rakibinin mevcut tüm altını sıfırlanır. 8. turun başında altınları iade edilir.',
    'type': 'opponent_delayed_gold_loss',
    'details': {'return_turn': 8},
  },
  'GENEROUS_SPONSOR': {
    'name': 'Cömert Sponsor',
    'description': 'Anında 150 Altın kazanırsın, rakibin ise 50 Altın kazanır.',
    'type': 'split_gold_reward',
    'details': {'player_gold': 150, 'opponent_gold': 50},
  },
  'INCOME_BOOST': {
    'name': 'Gelir Patlaması',
    'description':
        'Sonraki 4 tur boyunca "Gelir Al" butonundan 175 yerine 200 Altın alırsın.',
    'type': 'persistent_self_buff',
    'details': {'buff_type': 'income_boost', 'duration': 4, 'value': 200},
  },
  'LOAN_STAR': {
    'name': 'Kiralık Yıldız',
    'description':
        'Takımına bir sonraki maça kadar havuzdan rastgele bir süper yıldız kiralık olarak katılır. Maçtan sonra takımdan ayrılır.',
    'type': 'temporary_player',
  },
  'GIANT_KILLER': {
    'name': 'Dev Katili',
    'description':
        'Eğer takımının ortalama reytingi rakibinden düşükse, maçta tüm oyuncuların +5 Şut ve Hız kazanır.',
    'type': 'conditional_stat_boost',
  },
  'TACTIC_MASTER': {
    'name': 'Taktik Ustası',
    'description':
        'Seçili taktiğinin sağladığı pozitif bonuslar %20 daha etkili olur.',
    'type': 'persistent_multiplier',
    'details': {'tactic_effectiveness': 1.2},
  },
  'MANAGER_CHARISMA': {
    'name': 'Menajer Karizması',
    'description':
        'Takım uyumun kalıcı olarak +%7 artar ve maç kaybettiğinde moral bonusu kaybetmezsin.',
    'type': 'persistent_passive_effect',
    'details': {'effect_type': 'charisma'},
  },
  'FATES_TRADE': {
    'name': 'Kader Takası',
    'description':
        'Rakibinin tüm altını sana geçer ama senden rastgele bir oyuncu rakibe geçer.',
    'type': 'fates_trade',
  },
  'BARGAINING_POWER': {
    'name': 'Pazarlık Gücü (İndirim)',
    'description':
        'Sonraki 4 tur boyunca mağazadan satın aldığın tüm oyuncular %10 daha ucuz olur.',
    'type': 'persistent_self_buff',
    'details': {'buff_type': 'shop_discount', 'duration': 4, 'value': 0.90},
  },
};

final List<String> allAugmentIds = augments.keys.toList(growable: false);

const Map<String, Map<String, String>> specialMatchEvents = {
  'derbi_atesi': {
    'name': 'Derbi Atesi',
    'description':
        'Tribunler maçi elektriklendirdi. Tempo, ikili mucadele ve baski siddeti yukseliyor.',
    'intro':
        'Ozel Olay: Derbi atesi bu maca vurdu. Tribun baskisi her temasi daha sert hale getiriyor.',
  },
  'tribun_baskisi': {
    'name': 'Tribun Baskisi',
    'description':
        'Ev sahibi tribunu takimini ileri itiyor. Ev sahibi daha cesur, deplasman daha gergin oynuyor.',
    'intro':
        'Ozel Olay: Tribun baskisi hissediliyor. Ev sahibi enerjiyle cikti, deplasman diken ustunde.',
  },
  'kaygan_zemin': {
    'name': 'Kaygan Zemin',
    'description':
        'Zemin tutmuyor. Pas kalitesi ve denge dusuyor, sakatlik ve mudahale riski artiyor.',
    'intro':
        'Ozel Olay: Zemin beklenenden daha kaygan. Ayakta kalmak bile ayrica bir mücadele olacak.',
  },
  'sert_hakem': {
    'name': 'Sert Hakem',
    'description':
        'Hakem temaslara cok yakin. Kart cizgisi erken cekiliyor, savunmacilar daha dikkatli olmak zorunda.',
    'intro':
        'Ozel Olay: Hakem ilk dakikadan itibaren cizgiyi net cekti. Her mudahale incelemede.',
  },
  'erken_firtina': {
    'name': 'Erken Firtina',
    'description':
        'Iki takim da maca cok sert ve hizli basliyor. Ilk yarim saatte tempo ile baski normalin ustune cikiyor.',
    'intro':
        'Ozel Olay: Mac erken firtina modunda. Iki takim da ilk dakikalarda vitesi en uste cekti.',
  },
};

const List<Map<String, dynamic>> playerDataTemplate = [
  {
    'id': 'arda_01',
    'name': 'Arda',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 88,
      'savunma': 40,
      'dayaniklilik': 70,
      'sut': 92,
      'pas': 60,
      'hiz': 70,
    },
  },
  {
    'id': 'musa_01',
    'name': 'Musa',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 61,
      'savunma': 56,
      'dayaniklilik': 71,
      'sut': 51,
      'pas': 66,
      'hiz': 51,
    },
  },
  {
    'id': 'leo_01',
    'name': 'Leo',
    'mevki': 'Defans',
    'stats': {
      'hucum': 55,
      'savunma': 90,
      'dayaniklilik': 95,
      'sut': 40,
      'pas': 50,
      'hiz': 80,
    },
  },
  {
    'id': 'bora_01',
    'name': 'Bora',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 20,
      'savunma': 95,
      'dayaniklilik': 80,
      'sut': 0,
      'pas': 40,
      'hiz': 83,
    },
  },
  {
    'id': 'can_01',
    'name': 'Can',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 80,
      'savunma': 30,
      'dayaniklilik': 60,
      'sut': 85,
      'pas': 50,
      'hiz': 85,
    },
  },
  {
    'id': 'deniz_01',
    'name': 'Deniz',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 60,
      'savunma': 55,
      'dayaniklilik': 60,
      'sut': 55,
      'pas': 70,
      'hiz': 60,
    },
  },
  {
    'id': 'mert_01',
    'name': 'Mert',
    'mevki': 'Defans',
    'stats': {
      'hucum': 60,
      'savunma': 85,
      'dayaniklilik': 90,
      'sut': 50,
      'pas': 70,
      'hiz': 85,
    },
  },
  {
    'id': 'yusuf_01',
    'name': 'Yusuf',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 78,
      'savunma': 50,
      'dayaniklilik': 75,
      'sut': 70,
      'pas': 75,
      'hiz': 72,
    },
  },
  {
    'id': 'enes_01',
    'name': 'Enes',
    'mevki': 'Defans',
    'stats': {
      'hucum': 52,
      'savunma': 90,
      'dayaniklilik': 88,
      'sut': 40,
      'pas': 62,
      'hiz': 68,
    },
  },
  {
    'id': 'ronaldo_01',
    'name': 'Ronaldo',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 90,
      'savunma': 45,
      'dayaniklilik': 70,
      'sut': 85,
      'pas': 70,
      'hiz': 80,
    },
  },
  {
    'id': 'ugurcan_01',
    'name': 'Uğurcan',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 35,
      'savunma': 85,
      'dayaniklilik': 88,
      'sut': 5,
      'pas': 65,
      'hiz': 52,
    },
  },
  {
    'id': 'courtois_01',
    'name': 'Courtois',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 45,
      'savunma': 86,
      'dayaniklilik': 90,
      'sut': 4,
      'pas': 75,
      'hiz': 55,
    },
  },
  {
    'id': 'mertens_01',
    'name': 'Mertens',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 82,
      'savunma': 43,
      'dayaniklilik': 68,
      'sut': 77,
      'pas': 80,
      'hiz': 70,
    },
  },
  {
    'id': 'valverde_01',
    'name': 'Valverde',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 75,
      'savunma': 55,
      'dayaniklilik': 75,
      'sut': 85,
      'pas': 80,
      'hiz': 75,
    },
  },
  {
    'id': 'sara_01',
    'name': 'Sara',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 75,
      'savunma': 35,
      'dayaniklilik': 60,
      'sut': 65,
      'pas': 85,
      'hiz': 65,
    },
  },
  {
    'id': 'yunus_01',
    'name': 'Yunus',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 77,
      'savunma': 33,
      'dayaniklilik': 60,
      'sut': 75,
      'pas': 70,
      'hiz': 75,
    },
  },
  {
    'id': 'cuesta_01',
    'name': 'Cuesta',
    'mevki': 'Defans',
    'stats': {
      'hucum': 47,
      'savunma': 70,
      'dayaniklilik': 70,
      'sut': 30,
      'pas': 60,
      'hiz': 53,
    },
  },
  {
    'id': 'rodri_01',
    'name': 'Rodri',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 83,
      'savunma': 40,
      'dayaniklilik': 75,
      'sut': 83,
      'pas': 75,
      'hiz': 74,
    },
  },
  {
    'id': 'sanchez_01',
    'name': 'Sanchez',
    'mevki': 'Defans',
    'stats': {
      'hucum': 48,
      'savunma': 91,
      'dayaniklilik': 90,
      'sut': 39,
      'pas': 62,
      'hiz': 68,
    },
  },
  {
    'id': 'osimhen_01',
    'name': 'Osimhen',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 87,
      'savunma': 40,
      'dayaniklilik': 70,
      'sut': 83,
      'pas': 65,
      'hiz': 83,
    },
  },
  {
    'id': 'samet_01',
    'name': 'Samet',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 35,
      'savunma': 78,
      'dayaniklilik': 75,
      'sut': 0,
      'pas': 65,
      'hiz': 45,
    },
  },
  {
    'id': 'emir_01',
    'name': 'Emir',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 50,
      'savunma': 82,
      'dayaniklilik': 70,
      'sut': 11,
      'pas': 77,
      'hiz': 55,
    },
  },
  {
    'id': 'osman_01',
    'name': 'Osman',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 76,
      'savunma': 47,
      'dayaniklilik': 60,
      'sut': 79,
      'pas': 70,
      'hiz': 72,
    },
  },
  {
    'id': 'singo_01',
    'name': 'Singo',
    'mevki': 'Defans',
    'stats': {
      'hucum': 65,
      'savunma': 78,
      'dayaniklilik': 85,
      'sut': 40,
      'pas': 62,
      'hiz': 75,
    },
  },
  {
    'id': 'daniolmo_01',
    'name': 'Dani Olmo',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 75,
      'savunma': 42,
      'dayaniklilik': 70,
      'sut': 74,
      'pas': 68,
      'hiz': 78,
    },
  },
  {
    'id': 'havertz_01',
    'name': 'Havertz',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 77,
      'savunma': 43,
      'dayaniklilik': 66,
      'sut': 80,
      'pas': 77,
      'hiz': 77,
    },
  },
  {
    'id': 'ramazan_01',
    'name': 'Ramazan',
    'mevki': 'Defans',
    'stats': {
      'hucum': 65,
      'savunma': 71,
      'dayaniklilik': 78,
      'sut': 31,
      'pas': 62,
      'hiz': 70,
    },
  },
  {
    'id': 'kenan_yildiz_01',
    'name': 'Kenan Yıldız',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 84,
      'savunma': 30,
      'dayaniklilik': 75,
      'sut': 85,
      'pas': 70,
      'hiz': 83,
    },
  },
  {
    'id': 'icardi_01',
    'name': 'Mauro Icardi',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 88,
      'savunma': 35,
      'dayaniklilik': 70,
      'sut': 86,
      'pas': 68,
      'hiz': 75,
    },
  },
  {
    'id': 'rudiger_01',
    'name': 'Rüdiger',
    'mevki': 'Defans',
    'stats': {
      'hucum': 60,
      'savunma': 94,
      'dayaniklilik': 90,
      'sut': 45,
      'pas': 70,
      'hiz': 86,
    },
  },
  {
    'id': 'tarik_01',
    'name': 'Tarık',
    'mevki': 'Defans',
    'stats': {
      'hucum': 50,
      'savunma': 80,
      'dayaniklilik': 75,
      'sut': 30,
      'pas': 60,
      'hiz': 75,
    },
  },
  {
    'id': 'merih_demiral_01',
    'name': 'Merih Demiral',
    'mevki': 'Defans',
    'stats': {
      'hucum': 45,
      'savunma': 84,
      'dayaniklilik': 80,
      'sut': 35,
      'pas': 58,
      'hiz': 82,
    },
  },
  {
    'id': 'ersin_d_01',
    'name': 'Ersin D.',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 25,
      'savunma': 82,
      'dayaniklilik': 75,
      'sut': 10,
      'pas': 58,
      'hiz': 50,
    },
  },
  {
    'id': 'muslera_01',
    'name': 'Muslera',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 30,
      'savunma': 88,
      'dayaniklilik': 82,
      'sut': 10,
      'pas': 65,
      'hiz': 45,
    },
  },
  {
    'id': 'pedri_01',
    'name': 'Pedri',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 76,
      'savunma': 52,
      'dayaniklilik': 75,
      'sut': 55,
      'pas': 88,
      'hiz': 80,
    },
  },
  {
    'id': 'kerem_demirbay_01',
    'name': 'Kerem Demirbay',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 65,
      'savunma': 50,
      'dayaniklilik': 72,
      'sut': 74,
      'pas': 78,
      'hiz': 56,
    },
  },
  {
    'id': 'ramos_01',
    'name': 'Ramos',
    'mevki': 'Defans',
    'stats': {
      'hucum': 60,
      'savunma': 92,
      'dayaniklilik': 88,
      'sut': 55,
      'pas': 72,
      'hiz': 81,
    },
  },
  {
    'id': 'ozan_01',
    'name': 'Ozan',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 72,
      'savunma': 65,
      'dayaniklilik': 78,
      'sut': 70,
      'pas': 75,
      'hiz': 70,
    },
  },
  {
    'id': 'cenk_01',
    'name': 'Cenk',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 79,
      'savunma': 35,
      'dayaniklilik': 70,
      'sut': 80,
      'pas': 65,
      'hiz': 72,
    },
  },
  {
    'id': 'kaan_01',
    'name': 'Kaan',
    'mevki': 'Defans',
    'stats': {
      'hucum': 60,
      'savunma': 78,
      'dayaniklilik': 80,
      'sut': 50,
      'pas': 68,
      'hiz': 73,
    },
  },
  {
    'id': 'altay_01',
    'name': 'Altay',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 25,
      'savunma': 80,
      'dayaniklilik': 75,
      'sut': 5,
      'pas': 60,
      'hiz': 55,
    },
  },
  {
    'id': 'irfan_01',
    'name': 'İrfan',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 75,
      'savunma': 50,
      'dayaniklilik': 72,
      'sut': 78,
      'pas': 82,
      'hiz': 68,
    },
  },
  {
    'id': 'serdar_01',
    'name': 'Serdar',
    'mevki': 'Defans',
    'stats': {
      'hucum': 45,
      'savunma': 68,
      'dayaniklilik': 70,
      'sut': 30,
      'pas': 55,
      'hiz': 60,
    },
  },
  {
    'id': 'umut_01',
    'name': 'Umut',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 69,
      'savunma': 25,
      'dayaniklilik': 65,
      'sut': 70,
      'pas': 50,
      'hiz': 68,
    },
  },
  {
    'id': 'taylan_01',
    'name': 'Taylan',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 60,
      'savunma': 62,
      'dayaniklilik': 72,
      'sut': 55,
      'pas': 68,
      'hiz': 65,
    },
  },
  {
    'id': 'gokhan_01',
    'name': 'Gökhan',
    'mevki': 'Kaleci',
    'stats': {
      'hucum': 20,
      'savunma': 69,
      'dayaniklilik': 65,
      'sut': 10,
      'pas': 50,
      'hiz': 45,
    },
  },
  {
    'id': 'berkan_01',
    'name': 'Berkan',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 55,
      'savunma': 65,
      'dayaniklilik': 80,
      'sut': 50,
      'pas': 60,
      'hiz': 62,
    },
  },
  {
    'id': 'ali_01',
    'name': 'Ali',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 68,
      'savunma': 30,
      'dayaniklilik': 60,
      'sut': 65,
      'pas': 55,
      'hiz': 70,
    },
  },
  {
    'id': 'emre_01',
    'name': 'Emre',
    'mevki': 'Defans',
    'stats': {
      'hucum': 50,
      'savunma': 65,
      'dayaniklilik': 68,
      'sut': 40,
      'pas': 60,
      'hiz': 66,
    },
  },
];

const List<Map<String, dynamic>> loanStarsPool = [
  {
    'id': 'loan_kane',
    'name': 'Kiralık Kane',
    'mevki': 'Forvet',
    'stats': {
      'hucum': 95,
      'savunma': 48,
      'dayaniklilik': 80,
      'sut': 98,
      'pas': 80,
      'hiz': 75,
    },
  },
  {
    'id': 'loan_kdb',
    'name': 'Kiralık De Bruyne',
    'mevki': 'Orta Saha',
    'stats': {
      'hucum': 85,
      'savunma': 65,
      'dayaniklilik': 82,
      'sut': 90,
      'pas': 99,
      'hiz': 78,
    },
  },
  {
    'id': 'loan_vvd',
    'name': 'Kiralık Van Dijk',
    'mevki': 'Defans',
    'stats': {
      'hucum': 65,
      'savunma': 98,
      'dayaniklilik': 90,
      'sut': 60,
      'pas': 75,
      'hiz': 84,
    },
  },
];

final List<String> allMasterPlayerIds = playerDataTemplate
    .map((player) => player['id']! as String)
    .toList(growable: false);

const Map<String, String> infoTexts = {
  'mentality':
      '[b]Maç Mentalitesi[/b]\n\nTakımınızın maç içindeki genel risk seviyesini belirler. Hücum mentalitesi gol şansınızı artırır ancak takımınızı kontra ataklara karşı savunmasız bırakır ve oyuncuları daha hızlı yorar.',
  'in_possession':
      '[b]Top Bizdeyken[/b]\n\nTakımınızın topa sahipken nasıl davranacağını ayarlar.\n\n[b]Oyun Kurma Hızı:[/b] Topu ne kadar hızlı ileri taşıyacağınızı belirler.\n[b]Pas Odağı:[/b] Hücumları merkezden mi yoksa kanatlardan mı geliştireceğinizi seçer.',
  'chance_creation':
      '[b]Şans Yaratma[/b]\n\nHücum bölgesindeki son pas ve orta tercihlerini belirler.\n\n[b]Orta Tipi:[/b] Kanatlardan yapılacak ortaların türünü ayarlar.',
  'out_of_possession':
      '[b]Top Rakipteyken[/b]\n\nTakımınızın savunma yaparken nasıl organize olacağını belirler.\n\n[b]Savunma Derinliği:[/b] Savunma hattının ne kadar ileride veya geride kurulacağını ayarlar.\n[b]Ofsayt Taktiği:[/b] Savunma hattının ofsayt tuzağı kurup kurmayacağını belirler.',
  'pressing':
      '[b]Pres Yoğunluğu[/b]\n\nTakımınızın rakibe ne zaman ve ne kadar yoğun baskı yapacağını ayarlar. Yüksek pres, topu erken kazanma şansı sunar ama oyuncuları hızla yorar.',
};

const Map<String, List<String>> slotMevkiMap = {
  'GK': ['Kaleci'],
  'DEF1': ['Defans'],
  'DEF2': ['Defans'],
  'DEF3': ['Defans'],
  'MID1': ['Orta Saha'],
  'MID2': ['Orta Saha'],
  'MID3': ['Orta Saha'],
  'FWD1': ['Forvet'],
  'FWD2': ['Forvet'],
  'BENCH1': ['Forvet', 'Orta Saha', 'Defans', 'Kaleci'],
  'BENCH2': ['Forvet', 'Orta Saha', 'Defans', 'Kaleci'],
  'BENCH3': ['Forvet', 'Orta Saha', 'Defans', 'Kaleci'],
  'BENCH4': ['Forvet', 'Orta Saha', 'Defans', 'Kaleci'],
};

const Map<String, List<String>> activeSlotsByFormation = {
  '3-2-1': [
    'GK',
    'DEF1',
    'DEF2',
    'DEF3',
    'MID1',
    'MID2',
    'FWD1',
    'BENCH1',
    'BENCH2',
    'BENCH3',
    'BENCH4',
  ],
  '2-3-1': [
    'GK',
    'DEF1',
    'DEF2',
    'MID1',
    'MID2',
    'MID3',
    'FWD1',
    'BENCH1',
    'BENCH2',
    'BENCH3',
    'BENCH4',
  ],
  '2-2-2': [
    'GK',
    'DEF1',
    'DEF2',
    'MID1',
    'MID2',
    'FWD1',
    'FWD2',
    'BENCH1',
    'BENCH2',
    'BENCH3',
    'BENCH4',
  ],
};

const Map<String, Map<String, dynamic>> facilitiesData = {
  'saglik_merkezi': {
    'id': 'saglik_merkezi',
    'name': 'Modern Sağlık Merkezi',
    'cost': 350,
    'desc':
        'Maç içi sakatlık riskini ciddi oranda azaltır ve oyuncular daha geç yorulur.',
  },
  'ticari_stadyum': {
    'id': 'ticari_stadyum',
    'name': 'Ticari Stadyum Kompleksi',
    'cost': 400,
    'desc':
        'Tur atladığında pasif olarak düzenli (+45 Altın) ekstra gelir kazandırır.',
  },
  'vip_tribun': {
    'id': 'vip_tribun',
    'name': 'Ateşli VIP Taraftar',
    'cost': 300,
    'desc':
        'Kendi başlattığın maçlarda (İç Saha) takıma ekstra moral ve hücum coşkusu verir.',
  },
};

const Map<String, Map<String, String>> playerInstructions = {
  'GK': {
    'Libero Kaleci': 'Savunma arkasına atılan toplarda daha agresif çıkar.',
    'Topu Kısa Kullan': 'Oyun kurulumunda risk azaltılır, kısa pas öncelenir.',
    'Uzun Oyna': 'Hızlı geçiş için topu doğrudan ileri taşımaya çalışır.',
  },
  'DEF': {
    'Alanı Kapat': 'Pozisyon disiplinini korur, geride güvenliği artırır.',
    'Sert Müdahale': 'Top kapma ihtimali artar, faul riski yükselir.',
    'Bindirme Yap': 'Boş alan bulduğunda hücuma destek verir.',
  },
  'MID': {
    'Oyunu Yavaşlat': 'Tempo düşer, pas kalitesi artar.',
    'Riskli Pas': 'Daha dikine oynar, fırsat üretme potansiyeli yükselir.',
    'Ceza Sahasına Koşu': 'İkinci dalga hücum koşularına daha sık çıkar.',
  },
  'FWD': {
    'Önde Baskı': 'Rakip stoperlere ilk baskıyı yapar.',
    'Kanala Koş': 'Savunma arkasına çapraz koşularla boşluk arar.',
    'Hedef Santrfor': 'Topu saklayıp takım arkadaşlarını oyuna sokar.',
  },
};
